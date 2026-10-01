# Descriptive current-state codebase scorecard. Emits JSON to stdout. It is a snapshot, not a
# before/after measurement, and shows nothing about what caused a value to be what it is.
# Usage: pwsh -NoProfile -File scripts/metrics.ps1 [path ...]  (default: whole repo)
$ErrorActionPreference = 'SilentlyContinue'
$root = (git rev-parse --show-toplevel 2>$null); if (-not $root) { $root = (Get-Location).Path }
Set-Location $root
$paths = if ($args.Count -gt 0) { $args } else { @('.') }

function Count([string]$rx) {
    $files = Get-ChildItem -Path $paths -Recurse -File -Include *.java -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](target|build|out|bin|\.gradle|node_modules|dist)[\\/]' }
    if (-not $files) { return 0 }
    ($files | Select-String -Pattern $rx -ErrorAction SilentlyContinue | Measure-Object).Count
}

$m = [ordered]@{
    concatenated_logging               = (Count '\b(log|logger)\.(trace|debug|info|warn|error)\(\s*("[^"]*"\s*\+|String\.format\()')
    analyzer_suppressions              = (Count '//\s*(NOSONAR|NOPMD)|CHECKSTYLE[:.]OFF|@SuppressFBWarnings|@SuppressWarnings\(\s*\{?\s*"(all|PMD|checkstyle|java:S)')
    system_out_println                 = (Count 'System\.(out|err)\.print|\.printStackTrace\(\)')
    todo_hack_fixme                    = (Count '(TODO|HACK|FIXME)')
    not_implemented_throws             = (Count 'throw\s+new\s+UnsupportedOperationException')
    concrete_service_instantiation_dip = (Count 'new\s+[A-Za-z0-9_]+(Service|Repository|Handler|Manager)\(')
    field_injection                    = (Count '@Autowired\s+(private|protected|public)\s')
    weak_crypto_md5_sha1               = (Count '"(MD5|SHA-?1)"')
    concatenated_sql                   = (Count '(createQuery|createNativeQuery|executeQuery|executeUpdate|prepareStatement|query|queryForObject|queryForList|update)\(\s*"[^"]*"\s*\+')
    eager_fetch                        = (Count 'FetchType\.EAGER')
    money_double_float                 = (Count '\b(double|float|Double|Float)\s+[A-Za-z_]*(Amount|Balance|Price|Rate|Fee|Notional)')
    broad_catch                        = (Count 'catch\s*\(\s*(final\s+)?(Exception|Throwable|RuntimeException)\s+\w+\s*\)')
    test_annotations                   = (Count '@(Test|ParameterizedTest|RepeatedTest|TestFactory)\b')
    tests_skipped                      = (Count '@(Disabled|Ignore)\b|@Test\s*\([^)]*enabled\s*=\s*false')
    tautological_assert                = (Count 'assert(True\(\s*true|False\(\s*false)\s*[),]|assertThat\(\s*(true|false)\s*\)\.is(True|False)\(\)')
}

# --- Readiness signals: capability disclosure, NOT a gate ---
$ciPresent = (Test-Path 'bitbucket-pipelines.yml') -or (Test-Path 'bitbucket-pipelines.yaml') -or (Test-Path '.github/workflows') -or (Test-Path 'azure-pipelines.yml') -or (Test-Path 'bamboo-specs') -or (Test-Path 'Jenkinsfile')
$covPct = $null
# JaCoCo XML: Maven target/site/jacoco/jacoco.xml, Gradle build/reports/jacoco/**/*.xml. The
# report-level LINE counter is the whole-report line coverage.
$covFile = Get-ChildItem -Path . -Recurse -File -Include 'jacoco.xml', 'jacocoTestReport.xml' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]node_modules[\\/]' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($covFile) {
    try {
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
        $settings.XmlResolver = $null
        $reader = [System.Xml.XmlReader]::Create($covFile.FullName, $settings)
        try { $xml = New-Object System.Xml.XmlDocument; $xml.Load($reader) } finally { $reader.Close() }
        $line = @($xml.report.counter | Where-Object { $_.type -eq 'LINE' }) | Select-Object -First 1
        if ($line) {
            $covered = [double]$line.covered; $missed = [double]$line.missed
            if (($covered + $missed) -gt 0) { $covPct = [math]::Round($covered * 100 / ($covered + $missed), 1) }
        }
    } catch {}
}
if ($null -eq $covPct) {
    $covFile = Get-ChildItem -Path . -Recurse -File -Filter '*cobertura*.xml' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]node_modules[\\/]' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($covFile) { try { $xml = [xml](Get-Content $covFile.FullName -Raw); $lr = $xml.coverage.'line-rate'; if ($lr) { $covPct = [math]::Round([double]$lr * 100, 1) } } catch {} }
}
$buildFiles = Get-ChildItem -Path . -Recurse -File -Include pom.xml, *.gradle, *.gradle.kts -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](target|build|\.gradle|node_modules)[\\/]' }
$nullness = [bool]($buildFiles | Select-String -Pattern 'nullaway|checkerframework|jspecify' -ErrorAction SilentlyContinue | Select-Object -First 1)
$warnErr  = [bool]($buildFiles | Select-String -Pattern '-Werror|<failOnWarning>\s*true|failOnWarning\s*=\s*true|allWarningsAsErrors' -ErrorAction SilentlyContinue | Select-Object -First 1)
$r = [ordered]@{
    ci_present         = $ciPresent
    coverage_pct       = $covPct
    nullness_checked   = $nullness
    warnings_as_errors = $warnErr
    has_tests          = ($m.test_annotations -gt 0)
}
[pscustomobject]@{ stack = 'java'; scope = ($paths -join ' '); metrics = $m; readiness = $r } | ConvertTo-Json -Depth 4
