# Stop hook -- flag Boy Scout opportunities in modified .java files.
# Boy-scout hook for the supported native Windows PowerShell topology.
# CLAUDE scans and emits the Stop output shapes; SCAN queues findings and emits a Copilot-shaped
# response; DELIVER emits and deletes that queued response without scanning. These are script
# outputs: host firing and consumption are capability-specific. The advisory response uses
# additionalContext and never blocks.
#
# Advisory patterns related to AGENTS.md > Boy Scout Rule:
#   - string-concatenated or String.format logger calls (SLF4J placeholders instead)
#   - field injection (@Autowired on a field) where constructor injection is the convention
#   - read-style Spring Data calls in a @Transactional class with no readOnly = true
#   - unchecked Optional.get() (heuristic)

param(
    [ValidateSet('scan', 'deliver')]
    [string]$Mode
)

$ErrorActionPreference = 'SilentlyContinue'
$inputJson = [Console]::In.ReadToEnd()

$resolvedMode = if ($Mode) {
    $Mode.ToLowerInvariant()
} elseif ($inputJson -match 'hook_event_name') {
    'claude'
} elseif ($inputJson -match '(?i):\s*\x22(agentStop|Stop)\x22') {
    'scan'
} else {
    'deliver'
}

$candidateRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..'))
$repoRoot = (& git -C $candidateRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if (-not $repoRoot) { exit 0 }
$repoRoot = [IO.Path]::GetFullPath($repoRoot.Trim())

$stateDir = Join-Path $repoRoot '.claude\.state'
$queueFile = Join-Path $stateDir 'boy-scout-queue'
if ($resolvedMode -eq 'deliver') {
    if (Test-Path -LiteralPath $queueFile) {
        $queuedText = [string](Get-Content -LiteralPath $queueFile -Raw)
        if (-not [string]::IsNullOrWhiteSpace($queuedText)) {
            @{ additionalContext = $queuedText; hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $queuedText } } | ConvertTo-Json -Compress
        }
        Remove-Item -LiteralPath $queueFile -Force
    }
    exit 0
}

$changed = @()
$changed += & git -C $repoRoot diff --name-only -- '*.java'
$changed += & git -C $repoRoot diff --cached --name-only -- '*.java'
$changed += & git -C $repoRoot ls-files --others --exclude-standard -- '*.java'

$files = $changed |
    Where-Object { $_ -and $_.Trim() } |
    Sort-Object -Unique |
    Select-Object -First 30

if (-not $files) { exit 0 }

$findings = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($f in $files) {
    if ([string]::IsNullOrWhiteSpace($f)) { continue }
    $fullPath = Join-Path $repoRoot $f
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }

    # Skip test sources, generated sources, build output trees
    if ($f -match '(?i)(Test|Tests|IT|ITCase)\.java$') { continue }
    if ($f -match '(?i)(^|/)(src/test|target|build|out|generated|generated-sources)/') { continue }

    $checked++

    $lines = Get-Content -LiteralPath $fullPath
    if (-not $lines) { continue }
    $content = $lines -join "`n"

    # 1. String-concatenated or String.format logger calls (anti-pattern: SLF4J has placeholders)
    $concatLog = ($lines | Where-Object {
        $_ -match '\b(log|logger|LOG|LOGGER)\.(trace|debug|info|warn|error)\(\s*("[^"]*"\s*\+|String\.format\()' -and
        $_ -notmatch '^\s*//'
    }).Count
    if ($concatLog -gt 0) {
        $findings.Add("${f}: $concatLog string-concatenated or String.format logger call(s) -- advisory: SLF4J {} placeholders; change only when it serves the requested outcome or verification")
    }

    # 2. Field injection: @Autowired on a field rather than a constructor
    $fieldInjection = 0
    $lineArray = @($lines)
    for ($i = 0; $i -lt $lineArray.Count; $i++) {
        if ($lineArray[$i] -match '^\s*@Autowired\b(?!\s*\()') {
            $rest = ($lineArray[$i] -replace '^\s*@Autowired\b', '').Trim()
            $target = if ($rest) { $rest } elseif ($i + 1 -lt $lineArray.Count) { $lineArray[$i + 1].Trim() } else { '' }
            if ($target -match '^(private|protected|public|final|static|\s)*[\w.<>,?\[\] ]+\s+\w+\s*(=.*)?;$') { $fieldInjection++ }
        }
    }
    if ($fieldInjection -gt 0) {
        $findings.Add("${f}: $fieldInjection field-injected @Autowired member(s) -- advisory: prefer constructor injection when this class is the primary target of the change")
    }

    # 3. Read-style Spring Data calls in a @Transactional class without any readOnly = true (heuristic)
    if ($content -match '@Transactional\b' -and
        $content -match '\b\w*(Repository|EntityManager)\b' -and
        $content -match '\.(findAll|findById|findBy\w+|findAllBy\w+|getReferenceById|existsById|existsBy\w+|countBy\w+|count)\(' -and
        $content -notmatch 'readOnly\s*=\s*true' -and
        $content -notmatch '\b(Mongo|Reactive\w*|Elasticsearch|Redis|Cassandra)(Repository|Template)\b') {
        $findings.Add("${f}: read-style Spring Data query in a @Transactional class without any readOnly = true -- review for read-only opportunities")
    }

    # 4. No-argument .get() in a file that uses Optional -- weak proxy for unchecked Optional access.
    if ($content -match '\bOptional\b') {
        $getHits = ($lines | Where-Object { $_ -match '\.get\(\)' -and $_ -notmatch '^\s*//' }).Count
        if ($getHits -ge 3) {
            $findings.Add("${f}: $getHits no-argument .get() call(s) in a file using Optional -- confirm each Optional is checked, or prefer orElseThrow()")
        }
    }

    # 5. Commented-out code blocks -- runs of 2+ contiguous code-like // lines
    $maxRun = 0
    $run = 0
    foreach ($line in $lines) {
        if ($line -match '^\s*//\s*(.*)$') {
            $stripped = $Matches[1]
            if ($stripped -match '[;{}=]' -or $stripped -match '[a-zA-Z_]+\(') {
                $run++
                if ($run -gt $maxRun) { $maxRun = $run }
            } else { $run = 0 }
        } else { $run = 0 }
    }
    if ($maxRun -ge 2) {
        $findings.Add("${f}: commented-out code block ($maxRun+ contiguous lines) -- delete; version control preserves history (AGENTS.md > Boy Scout > Subtract)")
    }
}

if ($findings.Count -eq 0) { exit 0 }

# Dedup: skip output when this finding set matches the last fire's output.
$null = New-Item -ItemType Directory -Path $stateDir -Force
$hashFile = Join-Path $stateDir 'last-boy-scout-hash'
$joined = ($findings | Sort-Object) -join "`n"
$sha1 = [System.Security.Cryptography.SHA1]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
$currentHash = -join ($sha1.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
if (Test-Path $hashFile) {
    $prev = (Get-Content $hashFile -Raw)
    if ($prev) { $prev = $prev.Trim() }
    if ($prev -eq $currentHash) { exit 0 }
}
Set-Content -Path $hashFile -Value $currentHash -Encoding ASCII

$outLines = @("## Boy Scout candidates ($checked file(s) scanned)", '')
foreach ($finding in $findings) { $outLines += "- $finding" }
$outLines += ''
$outLines += "_These are advisory candidates. For a bug fix, act only when requested behaviour, caller/extension compatibility, or meaningful verification requires it; do not add a TODO for unrelated deferred cleanup._"
$text = $outLines -join "`n"

if ($resolvedMode -eq 'scan') {
    Set-Content -LiteralPath $queueFile -Value $text -Encoding UTF8
}

# The Claude-mode response includes findings as additionalContext plus a short systemMessage that
# reports the candidate count; whether a host consumes either field is capability-specific.
$summary = "Boy Scout: $($findings.Count) candidate(s) found across $checked file(s) (see AGENTS.md > Boy Scout Rule)."

if ($resolvedMode -eq 'claude') {
    @{ systemMessage = $summary; hookSpecificOutput = @{ hookEventName = 'Stop'; additionalContext = $text } } | ConvertTo-Json -Compress
} else {
    @{ additionalContext = $text; hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $text } } | ConvertTo-Json -Compress
}

exit 0
