#requires -version 5.1
[CmdletBinding()]
param(
    [switch]$Update,
    [string]$BaselinePath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $repoRoot 'quality/psscriptanalyzer-baseline.json'
}
Import-Module PSScriptAnalyzer -ErrorAction Stop

$issues = foreach ($sourcePath in @(
    (Join-Path $repoRoot 'scripts'),
    (Join-Path $repoRoot 'modules')
)) {
    Invoke-ScriptAnalyzer -Path $sourcePath -Recurse -Severity Warning, Information
}

$entries = @($issues |
    Group-Object RuleName, ScriptPath |
    ForEach-Object {
        $sample = $_.Group | Select-Object -First 1
        [pscustomobject]@{
            Rule = $sample.RuleName
            File = $sample.ScriptPath.Substring($repoRoot.Length + 1).Replace('\', '/')
            Count = $_.Count
        }
    } |
    Sort-Object Rule, File)

if ($Update) {
    $directory = Split-Path -Parent $BaselinePath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [pscustomobject]@{
        SchemaVersion = 1
        Scope = @('scripts', 'modules')
        Entries = $entries
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $BaselinePath -Encoding UTF8
    Write-Output "Baseline atualizada: $BaselinePath ($($issues.Count) avisos)."
    return
}

if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
    throw "Baseline ausente: $BaselinePath. Execute com -Update apos revisao."
}

$baseline = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
$expected = @{}
foreach ($entry in @($baseline.Entries)) { $expected["$($entry.Rule)|$($entry.File)"] = [int]$entry.Count }
$actual = @{}
foreach ($entry in $entries) { $actual["$($entry.Rule)|$($entry.File)"] = [int]$entry.Count }

$regressions = foreach ($key in $actual.Keys) {
    if (-not $expected.ContainsKey($key) -or $actual[$key] -gt $expected[$key]) {
        "${key}: $($actual[$key]) (baseline: $($expected[$key]))"
    }
}
if ($regressions) {
    $regressions | ForEach-Object { Write-Error "Novo ou ampliado aviso: $_" }
    exit 1
}

Write-Output "Baseline respeitada: $($issues.Count) avisos em $($entries.Count) combinacoes regra/arquivo."
