# Executa a suite de testes Pester 5 com gate de cobertura mínima.
# Falha (exit != 0) se houver testes falhando OU cobertura abaixo do limite.
#
# Uso:
#   pwsh -File tools/test-check.ps1 [-TestPath tests/unit] [-CoveragePath modules] [-MinCoverage 80.0]
#
# Requer Pester 5.x (Install-Module Pester -MinimumVersion 5.0).

[CmdletBinding()]
param(
    [string]$TestPath = 'tests/unit',
    [string]$CoveragePath = 'modules',
    [double]$MinCoverage = 80.0
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 })) {
    Write-Error "Pester 5.x nao encontrado. Instale com: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser"
    exit 2
}
Import-Module Pester -MinimumVersion 5.0 -Force

$config = New-PesterConfiguration
$config.Run.Path = (Resolve-Path $TestPath).Path
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = (Resolve-Path $CoveragePath).Path
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = (Join-Path $PSScriptRoot 'coverage-jacoco.xml')

$result = Invoke-Pester -Configuration $config

$lineCoverage = if ($result.CodeCoverage) { $result.CodeCoverage.CoveragePercent } else { 0.0 }

Write-Host ''
Write-Host ('Testes   : {0} total | {1} passou | {2} falhou | {3} pulou' -f $result.TotalCount, $result.PassedCount, $result.FailedCount, $result.SkippedCount)
Write-Host ('Cobertura: {0:N1}% (minimo {1:N1}%)' -f $lineCoverage, $MinCoverage)

if ($result.FailedCount -gt 0) {
    Write-Host "FALHA: testes com erro." -ForegroundColor Red
    exit 1
}

if ($lineCoverage -lt $MinCoverage) {
    Write-Host "FALHA: cobertura abaixo do minimo de $MinCoverage%." -ForegroundColor Red
    exit 1
}

Write-Host 'OK: testes e cobertura dentro do limite.' -ForegroundColor Green
exit 0
