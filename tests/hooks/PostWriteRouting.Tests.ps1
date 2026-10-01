# post-write.ps1 surface routing and self-filter behavior.
if (-not (Get-Command Reset-Tests -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot '_HookHarness.ps1') }
$hooks = (Resolve-Path (Join-Path $PSScriptRoot '..\..\.claude\hooks')).Path
$postWrite = Join-Path $hooks 'post-write.ps1'
Reset-Tests

$cases = @(
    @{ n='read-style payload (path, no content) self-filters to exit 0'; claude='{"tool_name":"Read","tool_input":{"file_path":"notes.txt"}}'; copilot='{"toolName":"view","toolArgs":{"path":"notes.txt"}}' },
    @{ n='write payload on a non-source path exits 0 before any build'; claude='{"tool_name":"Write","tool_input":{"file_path":"notes.txt","content":"hello world"}}'; copilot='{"toolName":"create","toolArgs":{"path":"notes.txt","file_text":"hello world"}}' }
)
Assert ($cases.Count -gt 0) 'post-write routing case table is empty'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('pwroute-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
# The hook bails before any build when no JDK is visible; every world below names one.
$oldJavaHome = $env:JAVA_HOME
$env:JAVA_HOME = $tmp
Push-Location $tmp
try {
    foreach ($surface in 'claude','copilot') {
        It "post-write allows build-free routing worlds ($surface)" {
            foreach ($case in $cases) {
                $decision = Get-Decision (Invoke-Hook $postWrite $case[$surface])
                Assert ($decision -eq 'ALLOW') "$($case.n): expected ALLOW, got $decision"
            }
        }
    }

    It 'missing Claude tool_name routes a real build failure to exit 2' {
        $failBin = Join-Path $tmp 'fail-bin'
        New-Item -ItemType Directory -Path $failBin -Force | Out-Null
        $mavenHook = [IO.File]::ReadAllText($postWrite).Contains('## mvn test-compile failed')
        if ($mavenHook) { [IO.File]::WriteAllText((Join-Path $tmp 'pom.xml'), '<project />') }
        else { [IO.File]::WriteAllText((Join-Path $tmp 'build.gradle'), "plugins { id 'java' }") }
        [IO.File]::WriteAllText((Join-Path $tmp 'Probe.java'), 'class Probe {}')
        [IO.File]::WriteAllText((Join-Path $failBin 'mvn.cmd'), "@echo simulated build failure 1>&2`r`n@exit /b 1`r`n")
        [IO.File]::WriteAllText((Join-Path $failBin 'gradle.bat'), "@echo simulated build failure 1>&2`r`n@exit /b 1`r`n")
        $oldPath = $env:PATH
        try {
            $env:PATH = $failBin + [IO.Path]::PathSeparator + $oldPath
            Remove-Item -LiteralPath (Join-Path $tmp '.claude/.state') -Recurse -Force -ErrorAction SilentlyContinue
            $event = '{"tool_input":{"file_path":"Probe.java","content":"broken"}}'
            Assert ((Get-Decision (Invoke-Hook $postWrite $event)) -eq 'BLOCK') 'empty-tool-name build failure did not use Claude exit-2 semantics'
        } finally { $env:PATH = $oldPath }
    }

    It 'a Java file with no Maven or Gradle build above it never invokes a build tool' {
        foreach ($artifact in 'pom.xml','build.gradle','settings.gradle','Probe.java','fail-bin','bin','.claude') {
            Remove-Item -LiteralPath (Join-Path $tmp $artifact) -Recurse -Force -ErrorAction SilentlyContinue
        }
        $bin = Join-Path $tmp 'bin'; $sentinel = Join-Path $tmp 'tool-invoked'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $tmp 'Probe.java'), 'class Probe {}')
        foreach ($shim in 'mvn.cmd','gradle.bat') { [IO.File]::WriteAllText((Join-Path $bin $shim), "@echo invoked> `"%POSTWRITE_TOOL_SENTINEL%`"`r`n@exit /b 1`r`n") }
        $oldPath = $env:PATH; $oldSentinel = $env:POSTWRITE_TOOL_SENTINEL
        try {
            $env:PATH = $bin + [IO.Path]::PathSeparator + $oldPath
            $env:POSTWRITE_TOOL_SENTINEL = $sentinel
            foreach ($event in @(
                '{"tool_name":"Write","tool_input":{"file_path":"Probe.java","content":"class Probe {}"}}',
                '{"toolName":"create","toolArgs":{"path":"Probe.java","file_text":"class Probe {}"}}'
            )) {
                Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue
                Assert ((Get-Decision (Invoke-Hook $postWrite $event)) -eq 'ALLOW') 'a build-less Java file was blocked'
                Assert (-not (Test-Path -LiteralPath $sentinel)) 'a build-less Java file invoked a build tool'
            }
        } finally { $env:PATH=$oldPath; $env:POSTWRITE_TOOL_SENTINEL=$oldSentinel }
    }

    It 'no visible JDK means no build is attempted' {
        Remove-Item -LiteralPath (Join-Path $tmp '.claude') -Recurse -Force -ErrorAction SilentlyContinue
        [IO.File]::WriteAllText((Join-Path $tmp 'pom.xml'), '<project />')
        [IO.File]::WriteAllText((Join-Path $tmp 'Probe.java'), 'class Probe {}')
        $bin = Join-Path $tmp 'bin'; $sentinel = Join-Path $tmp 'tool-invoked'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        foreach ($shim in 'mvn.cmd','gradle.bat') { [IO.File]::WriteAllText((Join-Path $bin $shim), "@echo invoked> `"%POSTWRITE_TOOL_SENTINEL%`"`r`n@exit /b 1`r`n") }
        $oldPath = $env:PATH; $oldSentinel = $env:POSTWRITE_TOOL_SENTINEL; $oldJava = $env:JAVA_HOME
        try {
            # Only the shim directory and the system directory: no java anywhere on PATH.
            $system = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32' } else { '/usr/bin' }
            $env:PATH = $bin + [IO.Path]::PathSeparator + $system
            $env:POSTWRITE_TOOL_SENTINEL = $sentinel
            $env:JAVA_HOME = ''
            Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue
            $event = '{"tool_name":"Write","tool_input":{"file_path":"Probe.java","content":"class Probe {}"}}'
            Assert ((Get-Decision (Invoke-Hook $postWrite $event)) -eq 'ALLOW') 'a JDK-less host blocked the write'
            Assert (-not (Test-Path -LiteralPath $sentinel)) 'a JDK-less host still invoked a build tool'
        } finally { $env:PATH=$oldPath; $env:POSTWRITE_TOOL_SENTINEL=$oldSentinel; $env:JAVA_HOME=$oldJava }
    }

    # Build-tool worlds for the throttle and budget cases: each tool branch the hook carries (Maven
    # test-compile, Gradle testClasses) runs against a shim on PATH.
    $hookText = [IO.File]::ReadAllText($postWrite)
    $worlds = @()
    if ($hookText.Contains('## mvn test-compile failed')) { $worlds += @{ Name = 'maven'; Shim = 'mvn.cmd'; Wrapper = 'mvnw.cmd'; Build = 'pom.xml'; BuildText = '<project />'; Offline = "[ERROR] Failed to execute goal on project app: Could not resolve dependencies: Cannot access central (https://repo.maven.apache.org/maven2) in offline mode and the artifact org.example:lib:jar:1.0 has not been downloaded from it before." } }
    if ($hookText.Contains('## gradle testClasses failed')) { $worlds += @{ Name = 'gradle'; Shim = 'gradle.bat'; Wrapper = 'gradlew.bat'; Build = 'build.gradle'; BuildText = "plugins { id 'java' }"; Offline = "Could not resolve all files for configuration ':compileClasspath'. No cached version of org.example:lib:1.0 available for offline mode." } }
    Assert ($worlds.Count -gt 0) 'post-write carries neither a Maven test-compile nor a Gradle testClasses branch'
    function Reset-BuildWorld($World, [string]$ShimBody) {
        foreach ($artifact in 'pom.xml','build.gradle','settings.gradle','mvnw.cmd','gradlew.bat','svc','bin','shim','fail-bin','.claude','Probe.java') {
            Remove-Item -LiteralPath (Join-Path $tmp $artifact) -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path (Join-Path $tmp 'shim') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $tmp $World.Build), $World.BuildText)
        [IO.File]::WriteAllText((Join-Path $tmp 'Probe.java'), 'class Probe {}')
        [IO.File]::WriteAllText((Join-Path $tmp "shim/$($World.Shim)"), $ShimBody)
        return '{"tool_name":"Write","tool_input":{"file_path":"Probe.java","content":"class Probe {}"}}'
    }

    It 'a second write inside the throttle window does not start another build' {
        foreach ($world in $worlds) {
            $counter = Join-Path $tmp 'build-count'
            Remove-Item -LiteralPath $counter -Force -ErrorAction SilentlyContinue
            $writeEvent = Reset-BuildWorld $world "@echo run>> `"%POSTWRITE_COUNTER%`"`r`n@exit /b 0`r`n"
            $oldPath = $env:PATH; $oldCounter = $env:POSTWRITE_COUNTER
            try {
                $env:PATH = (Join-Path $tmp 'shim') + [IO.Path]::PathSeparator + $oldPath
                $env:POSTWRITE_COUNTER = $counter
                foreach ($attempt in 1, 2) {
                    Assert ((Get-Decision (Invoke-Hook $postWrite $writeEvent)) -eq 'ALLOW') "$($world.Name): write $attempt was not allowed"
                }
                $runs = if (Test-Path -LiteralPath $counter) { @(Get-Content -LiteralPath $counter).Count } else { 0 }
                Assert ($runs -eq 1) "$($world.Name): expected exactly one run across two writes inside the window, got $runs"
            } finally { $env:PATH = $oldPath; $env:POSTWRITE_COUNTER = $oldCounter }
        }
    }

    # The harness waits for every process holding the hook's output pipe, so the elapsed bound also
    # proves the tool's process tree was killed rather than orphaned.
    It 'a build that outlives its budget is killed with its process tree and never blocks' {
        foreach ($world in $worlds) {
            # Sleeps about 30 s, then reports a failure the hook must never see.
            $writeEvent = Reset-BuildWorld $world "@ping -n 31 127.0.0.1 >nul`r`n@echo simulated build failure 1>&2`r`n@exit /b 1`r`n"
            $oldPath = $env:PATH; $oldBudget = $env:ATL_POSTWRITE_BUDGET_SEC
            try {
                $env:PATH = (Join-Path $tmp 'shim') + [IO.Path]::PathSeparator + $oldPath
                $env:ATL_POSTWRITE_BUDGET_SEC = '2'
                $clock = [Diagnostics.Stopwatch]::StartNew()
                $decision = Get-Decision (Invoke-Hook $postWrite $writeEvent)
                $elapsed = $clock.Elapsed.TotalSeconds
                Assert ($elapsed -lt 15) ("{0}: hook returned after {1:n1}s; the 2 s budget did not bound the run" -f $world.Name, $elapsed)
                Assert ($decision -eq 'ALLOW') "$($world.Name): a timed-out run must not block, got $decision"
            } finally { $env:PATH = $oldPath; $env:ATL_POSTWRITE_BUDGET_SEC = $oldBudget }
        }
    }

    # Dependencies missing from the local cache in offline mode mean the build examined nothing, so the
    # hook must say "not verified", never "fix before continuing", and must back off.
    It 'dependencies missing offline are reported as not verified, never as a failed build' {
        foreach ($world in $worlds) {
            $writeEvent = Reset-BuildWorld $world "@echo $($world.Offline)`r`n@exit /b 1`r`n"
            $oldPath = $env:PATH
            try {
                $env:PATH = (Join-Path $tmp 'shim') + [IO.Path]::PathSeparator + $oldPath
                $first = Invoke-Hook $postWrite $writeEvent
                Assert ((Get-Decision $first) -eq 'ALLOW') "$($world.Name): an offline resolution failure blocked the write as a failed build: $($first.Err.Trim())"
                Assert ($first.Out -match 'Build not verified' -and $first.Out -match 'network access') "$($world.Name): the hook did not say the build was not verified: $($first.Out.Trim())"
                $second = Invoke-Hook $postWrite $writeEvent
                Assert ((Get-Decision $second) -eq 'ALLOW' -and $second.Out -notmatch 'Build not verified') "$($world.Name): the unverified build was retried inside the back-off: $($second.Out.Trim())"
            } finally { $env:PATH = $oldPath }
        }
    }

    It "the project's wrapper is launched instead of a build tool on PATH" {
        foreach ($world in $worlds) {
            $sentinel = Join-Path $tmp 'path-tool-invoked'
            Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue
            $writeEvent = Reset-BuildWorld $world "@echo invoked> `"%POSTWRITE_TOOL_SENTINEL%`"`r`n@exit /b 0`r`n"
            [IO.File]::WriteAllText((Join-Path $tmp $world.Wrapper), "@echo wrapper compile error 1>&2`r`n@exit /b 1`r`n")
            $oldPath = $env:PATH; $oldSentinel = $env:POSTWRITE_TOOL_SENTINEL
            try {
                $env:PATH = (Join-Path $tmp 'shim') + [IO.Path]::PathSeparator + $oldPath
                $env:POSTWRITE_TOOL_SENTINEL = $sentinel
                $result = Invoke-Hook $postWrite $writeEvent
                Assert ((Get-Decision $result) -eq 'BLOCK' -and $result.Err -match 'wrapper compile error') "$($world.Name): the wrapper's failure was not reported: $($result.Err.Trim())"
                Assert (-not (Test-Path -LiteralPath $sentinel)) "$($world.Name): the build tool on PATH ran although the project has a wrapper"
            } finally { $env:PATH = $oldPath; $env:POSTWRITE_TOOL_SENTINEL = $oldSentinel }
        }
    }

    if (@($worlds | Where-Object { $_.Name -eq 'maven' }).Count -eq 0) {
        Skip 'a nested Maven module builds offline through its reactor root' 'this post-write carries no Maven branch' -Invariant
    } else {
        It 'a nested Maven module builds offline through its reactor root' {
            $world = @($worlds | Where-Object { $_.Name -eq 'maven' })[0]
            $argsFile = Join-Path $tmp 'mvn-args'
            Remove-Item -LiteralPath $argsFile -Force -ErrorAction SilentlyContinue
            $null = Reset-BuildWorld $world "@echo %*> `"%POSTWRITE_ARGS%`"`r`n@exit /b 0`r`n"
            New-Item -ItemType Directory -Path (Join-Path $tmp 'svc/src/main/java') -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $tmp 'svc/pom.xml'), '<project />')
            [IO.File]::WriteAllText((Join-Path $tmp 'svc/src/main/java/Probe.java'), 'class Probe {}')
            $oldPath = $env:PATH; $oldArgs = $env:POSTWRITE_ARGS
            try {
                $env:PATH = (Join-Path $tmp 'shim') + [IO.Path]::PathSeparator + $oldPath
                $env:POSTWRITE_ARGS = $argsFile
                $event = '{"tool_name":"Write","tool_input":{"file_path":"svc/src/main/java/Probe.java","content":"class Probe {}"}}'
                Assert ((Get-Decision (Invoke-Hook $postWrite $event)) -eq 'ALLOW') 'a passing reactor build blocked the write'
                Assert (Test-Path -LiteralPath $argsFile) 'the reactor build was never started'
                $recorded = [IO.File]::ReadAllText($argsFile)
                Assert ($recorded -match '"-o"' -and $recorded -match '"-pl" "svc" "-am"' -and $recorded -match '"test-compile"') "unexpected Maven arguments: $recorded"
            } finally { $env:PATH = $oldPath; $env:POSTWRITE_ARGS = $oldArgs }
        }
    }

    # Every case above invokes post-write.ps1 directly. The agent host does not: the registration
    # carries "shell": "powershell", so the whole command STRING runs inside an outer PowerShell, and
    # `-Command` collapses a failing native command's exit code to 1 -- the build failure is then a
    # non-blocking hook error and never reaches the agent. Read the command registered for THIS host
    # and launch it as the host does, over a fixture repo holding the shipped hook and a failing
    # build tool. The registered path is repo-root-relative, so the fixture carries the hook.
    $registrationRelative = if ($PSVersionTable.PSVersion.Major -ge 6) { '.claude/settings.json' } else { '.claude/settings.windows.json' }
    $expectedInterpreter = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' }
    It "registered post-write command reports a build failure with exit 2 through the host's outer -Command shell ($registrationRelative)" {
        $registrationPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path $registrationRelative
        Assert (Test-Path -LiteralPath $registrationPath -PathType Leaf) "registration file not found: $registrationRelative"
        $registration = [IO.File]::ReadAllText($registrationPath) | ConvertFrom-Json
        $registered = @(foreach ($group in @($registration.hooks.PostToolUse)) {
            foreach ($entry in @($group.hooks)) { if ([string]$entry.command -match 'post-write\.ps1') { [string]$entry.command } }
        })
        Assert ($registered.Count -eq 1) "expected exactly one registered post-write command in $registrationRelative, found $($registered.Count)"
        $command = $registered[0]
        Assert ((($command -split '\s+')[0]) -ceq $expectedInterpreter) "$registrationRelative registers '$((($command -split '\s+')[0]))', not '$expectedInterpreter'; this leg would relaunch the other PowerShell host"
        foreach ($world in $worlds) {
            $writeEvent = Reset-BuildWorld $world "@echo simulated build failure 1>&2`r`n@exit /b 1`r`n"
            New-Item -ItemType Directory -Path (Join-Path $tmp '.claude/hooks') -Force | Out-Null
            Copy-Item -LiteralPath $postWrite -Destination (Join-Path $tmp '.claude/hooks/post-write.ps1') -Force
            $oldPath = $env:PATH
            try {
                $env:PATH = (Join-Path $tmp 'shim') + [IO.Path]::PathSeparator + $oldPath
                $result = Invoke-RawProcess -FileName (Get-PsExe) -Arguments @('-NoProfile', '-Command', $command) -Stdin $writeEvent
                Assert ($result.Exit -eq 2) "$($world.Name): failing build exited $($result.Exit) through the outer -Command shell, not 2; the host reads anything but 2 as a non-blocking error and the agent is never told. stderr: $($result.Err.Trim())"
                Assert ($result.Err -match 'fix before continuing') "$($world.Name): the outer -Command shell lost the failure report on stderr: $($result.Err.Trim())"
            } finally { $env:PATH = $oldPath }
        }
    }
} finally {
    Pop-Location
    $env:JAVA_HOME = $oldJavaHome
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

exit (Write-TestSummary 'PostWriteRouting.Tests')
