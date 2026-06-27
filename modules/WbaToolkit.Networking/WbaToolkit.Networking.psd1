@{
    RootModule        = 'WbaToolkit.Networking.psm1'
    ModuleVersion     = '2.0.1'
    GUID              = 'f2d5f2d1-5e5f-4d5b-9af2-8f0f7a0e0e4a'
    Author            = 'wbaamaral'
    CompanyName       = 'wbaamaral'
    Copyright         = '(c) wbaamaral. All rights reserved.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-NetworkContext',
        'Test-GatewayConnectivity',
        'Test-DnsResolution',
        'Test-IcmpConnectivity',
        'Test-TcpPortConnectivity',
        'Test-UdpPortConnectivity',
        'Test-LocalTcpListener',
        'Test-LocalUdpListener',
        'New-ConnectivityTestPlan',
        'Invoke-ConnectivityTest',
        'Invoke-ConnectivityWizard',
        'Invoke-TargetConnectivityTest',
        'Invoke-TargetConnectivityWizard',
        'Show-ConnectivityReport',
        'Export-ConnectivityReport',
        'Export-ConnectivityReportPdf'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
