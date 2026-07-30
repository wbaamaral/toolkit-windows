@{
    RootModule        = 'WbaToolkit.Services.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b3c4d5e6-f7a8-9012-bcde-f34567890abc'
    Author            = 'wbaamaral'
    CompanyName       = 'wbaamaral'
    Copyright         = '(c) wbaamaral. All rights reserved.'
    Description       = 'Gerenciamento de servicos Windows: listar, iniciar, parar, reiniciar, configurar inicializacao e conta de logon.'
    PowerShellVersion = '5.1'
    RequiredModules   = @(
        @{ ModuleName = 'WbaToolkit.Core'; ModuleVersion = '1.0.0' }
    )
    FunctionsToExport = @(
        'Get-WindowsServiceStatus',
        'Get-WindowsServiceDetail',
        'Start-WindowsService',
        'Stop-WindowsService',
        'Restart-WindowsService',
        'Set-WindowsServiceStartup',
        'Set-WindowsServiceAccount',
        'Invoke-ServiceManager'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('WBA', 'Services', 'Windows', 'Servicos') } }
}
