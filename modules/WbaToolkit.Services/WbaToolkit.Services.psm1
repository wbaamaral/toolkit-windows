Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
    . $file.FullName
}

$publicPath = Join-Path $PSScriptRoot 'Public'
foreach ($file in @(Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File)) {
    . $file.FullName
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
