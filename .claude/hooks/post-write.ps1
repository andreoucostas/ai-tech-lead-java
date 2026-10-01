# PostToolUse hook -- incremental offline Maven/Gradle compile (main + test sources) after a write/edit
# on build-relevant files (.java sources + build inputs: pom.xml, *.gradle, *.gradle.kts,
# gradle/libs.versions.toml).
# Tool surfaces handled:
#   Claude Code (CLI + VS Code extension)  -- tool_name in {Write,Edit}; path at tool_input.file_path
#   GitHub Copilot (cloud agent + CLI)     -- toolName  in {edit,create}; path at toolArgs.filePath
# Throttled to one build per 60 seconds to avoid stomping on a long-running compile.

$ErrorActionPreference = 'SilentlyContinue'

# Bounded build. The agent host waits for this hook (Claude Code's default hook timeout is 600 s), so
# the tool runs as a child process until the deadline: 45 s, or ATL_POSTWRITE_BUDGET_SEC (whole
# seconds, 1-600) when set in the hook's environment. On expiry the whole process tree is killed.
# Returns $null when the result is unknown -- no launchable tool, a failed launch, or an exceeded
# budget -- so an unverified build is never reported as broken.
function Get-BuildDeadline {
    $budget = 45
    $requested = 0
    if ([int]::TryParse([string]$env:ATL_POSTWRITE_BUDGET_SEC, [ref]$requested) -and $requested -ge 1 -and $requested -le 600) {
        $budget = $requested
    }
    return [DateTime]::UtcNow.AddSeconds($budget)
}

function Invoke-BoundedTool([string]$Name, [string[]]$Arguments, [string]$WorkDir, [DateTime]$Deadline) {
    # Only files CreateProcess starts directly: the wrappers' and distributions' extensionless shell
    # scripts (mvnw, gradlew, mvn, gradle) cannot be launched by Process.Start on Windows.
    $exe = @(Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -match '\.(exe|cmd|bat)$' } | Select-Object -First 1)
    if ($exe.Count -eq 0) { return $null }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe[0].Source
        $psi.Arguments = (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
        $psi.WorkingDirectory = $WorkDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
    } catch { return $null }
    # The stream reads share the deadline: a tool that exits while a daemon it spawned still holds
    # the output pipe must not stall the turn either.
    $done = $proc.WaitForExit([int][Math]::Max(0, ($Deadline - [DateTime]::UtcNow).TotalMilliseconds))
    if ($done) {
        $done = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($stdout, $stderr),
            [int][Math]::Max(0, ($Deadline - [DateTime]::UtcNow).TotalMilliseconds))
    }
    if (-not $done) {
        & taskkill.exe /T /F /PID $proc.Id *> $null
        return $null
    }
    # javac errors reach stdout through Maven and stderr through Gradle: keep both, drop the build
    # tools' generic help and banner lines and the JVM's option banner, and keep the tail.
    $noise = '^\[(ERROR|INFO|WARNING)\]\s*$|-> \[Help \d+\]|^\[ERROR\] \[Help \d+\]|To see the full stack trace of the errors|Re-run Maven using the -X switch|For more information about the errors and possible solutions|^\* Try:|^> Run with --(stacktrace|info|debug|scan)|^> Get more help at|^BUILD FAILED in |^\* Get more help at|^Picked up (JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|JDK_JAVA_OPTIONS):'
    $all = @(@($stdout.Result -split "\r?\n") + @($stderr.Result -split "\r?\n") | Where-Object { $_ -ne '' -and $_ -notmatch $noise })
    # Maven prints the compiler errors once under COMPILATION ERROR and again after "Failed to execute
    # goal"; keep the first copy so the tail is not spent on the repeat.
    $goal = -1
    for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -match 'Failed to execute goal .*Compilation failure') { $goal = $i; break } }
    if ($goal -ge 1 -and @($all[0..($goal - 1)] | Where-Object { $_ -match 'COMPILATION ERROR' }).Count -gt 0) { $all = @($all[0..$goal]) }
    # Gradle repeats them under "What went wrong"; keep the first copy and the failed task's name.
    $failure = -1
    for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -match '^FAILURE: Build failed') { $failure = $i; break } }
    if ($failure -ge 1 -and @($all[0..($failure - 1)] | Where-Object { $_ -match ': error: ' }).Count -gt 0) {
        $task = @($all[$failure..($all.Count - 1)] | Where-Object { $_ -match '^Execution failed for task' } | Select-Object -First 1)
        $all = @($all[0..($failure - 1)]) + $task
    }
    $lines = @($all | Select-Object -Last 25)
    return [pscustomobject]@{ Code = $proc.ExitCode; Lines = $lines }
}

$null = New-Item -ItemType Directory -Path .claude\.state -Force

$inputJson = [Console]::In.ReadToEnd()
$filePath = ''
# Pre-declare so a malformed/empty payload leaves $tn = '' (not $null): the surface-routing at the
# end uses `$tn -eq ''` for Claude's empty-case exit-2 path, and $null -eq '' is False in PowerShell
# -- which would misroute a build failure to the Copilot exit-0 branch. Keeping it '' preserves the
# intended Claude empty-payload branch.
$tn = ''

if (-not [string]::IsNullOrEmpty($inputJson)) {
    try {
        $obj = $inputJson | ConvertFrom-Json
        $tn = if ($obj.tool_name) { [string]$obj.tool_name } elseif ($obj.toolName) { [string]$obj.toolName } else { '' }

        # Claude Code: tool_input.file_path
        if ($obj.tool_input) {
            if ($obj.tool_input.file_path) { $filePath = [string]$obj.tool_input.file_path }
            elseif ($obj.tool_input.filePath) { $filePath = [string]$obj.tool_input.filePath }
        }
        # Copilot: toolArgs is a parsed object (per spec), not a JSON string. Try object access first,
        # fall back to string parse for older payload shapes.
        $ta = $obj.toolArgs
        if ($ta -is [string]) { try { $ta = $ta | ConvertFrom-Json } catch { $ta = $null } }
        if ([string]::IsNullOrEmpty($filePath) -and $ta) {
            if ($ta.filePath) { $filePath = [string]$ta.filePath }
            elseif ($ta.file_path) { $filePath = [string]$ta.file_path }
            elseif ($ta.path) { $filePath = [string]$ta.path }
        }

        # Self-filter -- Copilot's hooks.json has no matcher, so gate here. Mirror guard.*: accept
        # known write tools (Claude Write/Edit, Copilot CLI edit/create) OR any tool carrying a file
        # path + content. The path+content arm covers VS Code agent mode's camelCase write tools
        # (str_replace/insert/create), which can't be enumerated; requiring content (not just a path)
        # keeps read-style tools from triggering a build.
        $contentParts = @($obj.tool_input.content, $obj.tool_input.new_string, $obj.tool_input.newString,
                          $obj.tool_input.file_text, $obj.tool_input.new_str, $obj.tool_input.text,
                          $ta.content, $ta.new_string, $ta.newString, $ta.file_text, $ta.new_str, $ta.text) |
                         Where-Object { $_ }
        $knownWrite = (@('Write','Edit','edit','create') -contains $tn) -or ($tn -eq '')
        if (-not ($knownWrite -or ($filePath -and $contentParts))) { exit 0 }
    } catch { }
}

if ([string]::IsNullOrEmpty($filePath) -and $env:CLAUDE_FILE_PATH) {
    $filePath = $env:CLAUDE_FILE_PATH
}

if ([string]::IsNullOrEmpty($filePath)) { exit 0 }
# Trigger on what the compile actually consumes: Java sources plus the build definition. A broken
# pom.xml, build script or version catalog breaks the build as surely as a .java edit; resources and
# other files stay excluded -- a compile cannot catch their breakage.
$normalized = $filePath -replace '\\', '/'
if ($normalized -notmatch '(\.java|(^|/)pom\.xml|\.gradle|\.gradle\.kts|(^|/)libs\.versions\.toml)$') { exit 0 }

# Bail cleanly if no JDK is visible: the build tools cannot start without one.
if ([string]::IsNullOrEmpty($env:JAVA_HOME) -and -not (Get-Command java -CommandType Application -ErrorAction SilentlyContinue)) { exit 0 }

$fileDir = Split-Path -Parent $filePath
if ([string]::IsNullOrEmpty($fileDir)) { $fileDir = '.' }
try { $dir = (Resolve-Path -LiteralPath $fileDir -ErrorAction Stop).Path } catch { exit 0 }

# Discover the build: walk up from the written file. The first directory holding a build file decides
# the tool (Gradle when it holds a Gradle build or settings file and either a Gradle wrapper or no
# pom.xml; otherwise Maven). Every walk stops at the Git root, so a repository nested in another
# project's directory is never built as part of it.
function Test-Any([string]$Dir, [string[]]$Names) {
    foreach ($n in $Names) { if (Test-Path -LiteralPath (Join-Path $Dir $n)) { return $true } }
    return $false
}
function Get-Ancestors([string]$Start) {
    $chain = @()
    $probe = $Start
    while ($probe) {
        $chain += $probe
        if (Test-Path -LiteralPath (Join-Path $probe '.git')) { break }
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $probe) { break }
        $probe = $parent
    }
    return , $chain
}
$gradleFiles = @('settings.gradle', 'settings.gradle.kts', 'build.gradle', 'build.gradle.kts')
$ancestors = Get-Ancestors $dir
$tool = $null
$module = $null
foreach ($probe in $ancestors) {
    $hasPom = Test-Path -LiteralPath (Join-Path $probe 'pom.xml')
    $hasGradle = Test-Any $probe $gradleFiles
    if (-not $hasPom -and -not $hasGradle) { continue }
    if ($hasGradle -and (-not $hasPom -or (Test-Path -LiteralPath (Join-Path $probe 'gradlew.bat')))) { $tool = 'gradle' } else { $tool = 'maven' }
    $module = $probe
    break
}
if (-not $tool) { exit 0 }

$root = $module
$extraArgs = @()
if ($tool -eq 'maven') {
    # The reactor root: the nearest ancestor marked by .mvn or a Maven wrapper, else the topmost
    # directory holding a pom.xml. A nested module builds through the reactor (-pl -am), so sibling
    # modules it depends on compile from source instead of from a stale local repository.
    $marked = $null
    $topmost = $module
    foreach ($probe in (Get-Ancestors $module)) {
        if (-not $marked -and (Test-Any $probe @('.mvn', 'mvnw.cmd'))) { $marked = $probe }
        if (Test-Path -LiteralPath (Join-Path $probe 'pom.xml')) { $topmost = $probe }
    }
    $root = if ($marked -and (Test-Path -LiteralPath (Join-Path $marked 'pom.xml'))) { $marked } else { $topmost }
    if ($root -ne $module) {
        $relative = ($module.Substring($root.Length).TrimStart('\', '/')) -replace '\\', '/'
        $extraArgs = @('-pl', $relative, '-am')
    }
    $launcher = if (Test-Path -LiteralPath (Join-Path $root 'mvnw.cmd')) { Join-Path $root 'mvnw.cmd' } else { 'mvn' }
    $buildArgs = @('-q', '-B', '-o') + $extraArgs + @('test-compile')
    $label = 'mvn test-compile'
    $failHeader = '## mvn test-compile failed'
} else {
    # The Gradle build root: the nearest ancestor holding a settings file, else the module itself.
    foreach ($probe in $ancestors) {
        if (Test-Any $probe @('settings.gradle', 'settings.gradle.kts')) { $root = $probe; break }
    }
    $launcher = if (Test-Path -LiteralPath (Join-Path $root 'gradlew.bat')) { Join-Path $root 'gradlew.bat' } else { 'gradle' }
    $buildArgs = @('--offline', '-q', 'testClasses')
    $label = 'gradle testClasses'
    $failHeader = '## gradle testClasses failed'
}
# Bail cleanly when neither the project's wrapper nor a build tool on PATH can be launched.
if (-not (Get-Command $launcher -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -match '\.(exe|cmd|bat)$' })) { exit 0 }

# Throttle: skip if a build was started within the last 60 seconds.
$stamp = '.claude\.state\last-build-ts'
# UTC integer epoch. NOT Get-Date -UFormat %s: under Windows PowerShell 5.1 that returns a
# fractional local-time string, and [double]::Parse is culture-sensitive -- in comma-decimal
# locales (de-DE/el-GR/fr-FR) the dot is a group separator, so the value overflows Int32 and
# throws on every write. This form is culture-free, integer, and UTC.
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if (Test-Path $stamp) {
    $lastRaw = Get-Content $stamp -Raw
    if ($lastRaw) {
        $last = 0
        if ([int]::TryParse($lastRaw.Trim(), [ref]$last) -and ($now - $last) -lt 60) {
            exit 0
        }
    }
}
Set-Content -Path $stamp -Value $now -Encoding ASCII

# Only surface output on failure — emitting the build summary every successful write wastes context tokens.
$deadline = Get-BuildDeadline
$run = Invoke-BoundedTool $launcher $buildArgs $root $deadline
# A module the reactor does not list (a standalone project nested under another POM) builds on its own.
if ($run -and $run.Code -ne 0 -and $extraArgs.Count -gt 0 -and
    @($run.Lines | Where-Object { $_ -match 'Could not find the selected project in the reactor' }).Count -gt 0) {
    if (Test-Path -LiteralPath (Join-Path $module 'mvnw.cmd')) { $launcher = Join-Path $module 'mvnw.cmd' }
    $run = Invoke-BoundedTool $launcher @('-q', '-B', '-o', 'test-compile') $module $deadline
}
if ($null -eq $run) {
    # Not verified (budget exceeded or no launch): back off for 300 s so a build that cannot finish
    # inside the budget does not cost the agent another full budget on the next write.
    Set-Content -Path $stamp -Value ($now + 300 - 60) -Encoding ASCII
    exit 0
}
if ($run.Code -eq 0) { exit 0 }

# The build examined nothing when it could not start or resolve: dependencies or plugins missing from
# the local Maven/Gradle cache in offline mode, a wrapper that cannot download its distribution, no
# usable JDK, or a project the tool could not select. Say so instead of reporting a broken build,
# and back off like a timeout.
$notVerified = '(?i)offline mode|No cached version|Could not resolve all (files|dependencies|artifacts) for configuration|could not resolve plugin artifact|was not found in any of the following sources|Could not find the selected project in the reactor|Task ''[^'']+'' not found|JAVA_HOME|no ''java'' command could be found|Cannot find a Java installation|No locally installed toolchains|release version \d+ not supported|invalid (target|source) release|Unsupported class file major version|services\.gradle\.org|Failed to fetch|Cannot download|UnknownHostException'
if (@($run.Lines | Where-Object { $_ -match $notVerified }).Count -gt 0) {
    Set-Content -Path $stamp -Value ($now + 300 - 60) -Encoding ASCII
    $note = "Build not verified: $label could not resolve its dependencies offline or could not start a JDK; run the build once with network access (and a JDK on JAVA_HOME or PATH) to enable the post-write build check."
    if ($tn -ceq 'Edit' -or $tn -ceq 'Write' -or $tn -eq '') {
        (@{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $note } } | ConvertTo-Json -Compress)
    } else {
        (@{ additionalContext = $note } | ConvertTo-Json -Compress)
    }
    exit 0
}

# Clear the throttle stamp so the next write rebuilds instead of skipping a known-broken build.
Remove-Item $stamp -Force

$msg = "$failHeader -- fix before continuing:`n" + ($run.Lines -join "`n")

# Surface per surface, discriminating by tool-name casing (mirror guard.ps1). Claude Code is the
# only surface consuming exit 2 + stderr; its tools are PascalCase Edit/Write -- and the ambiguous
# empty case routes here too, since its PostToolUse matcher only fires on Write|Edit.
# -ceq is required: case-insensitive -eq would route Copilot's lowercase 'edit' here by mistake.
if ($tn -ceq 'Edit' -or $tn -ceq 'Write' -or $tn -eq '') {
    [Console]::Error.WriteLine($msg)
    exit 2
}

# Everything else -- Copilot CLI (lowercase edit/create) AND VS Code agent mode (camelCase
# str_replace/insert/etc.) -- is sent the JSON additionalContext shape below, but a live sentinel
# canary (Copilot CLI 1.0.68, 2026-07-04) found the CLI model does NOT consume postToolUse stdout;
# this branch is emit-for-forward-compat only (see docs/enforcement-surfaces.md). VS Code unverified.
(@{ additionalContext = $msg } | ConvertTo-Json -Compress)
exit 0
