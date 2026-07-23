[CmdletBinding()]
param()

$coreModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $coreModulePath -Force -ErrorAction Stop

$publicPath  = Join-Path $PSScriptRoot 'Public'
$privatePath = Join-Path $PSScriptRoot 'Private'

Get-ChildItem -Path $publicPath, $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object {
        . $_.FullName
    }

Export-ModuleMember -Function @(
    'Get-NetworkContext',
    'Test-GatewayConnectivity',
    'Test-DnsResolution',
    'Test-IcmpConnectivity',
    'Test-TcpPortConnectivity',
    'Test-UdpPortConnectivity',
    'Test-LocalTcpListener',
    'Test-LocalUdpListener',
    'Test-DownloadSpeed',
    'New-ConnectivityTestPlan',
    'Invoke-ConnectivityTest',
    'Invoke-ConnectivityWizard',
    'Invoke-TargetConnectivityTest',
    'Invoke-TargetConnectivityWizard',
    'Show-ConnectivityReport',
    'Export-ConnectivityReport',
    'Export-ConnectivityReportPdf'
)
