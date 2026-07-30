# Projeto: wba-toolkit
# Autor: wbaamaral

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path -LiteralPath $privatePath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path -LiteralPath $publicPath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Get-StartupItem'
    'Disable-StartupItem'
    'Enable-StartupItem'
    'Remove-StartupItem'
    'Show-StartupItem'
    'Invoke-StartupManager'
    'Get-ServiceStartupState'
)
