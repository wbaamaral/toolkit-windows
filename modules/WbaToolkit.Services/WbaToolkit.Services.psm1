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
    'Get-WindowsServiceStatus',
    'Get-WindowsServiceDetail',
    'Start-WindowsService',
    'Stop-WindowsService',
    'Restart-WindowsService',
    'Set-WindowsServiceStartup',
    'Set-WindowsServiceAccount',
    'Invoke-ServiceManager'
)
