@{
    ModuleVersion     = '1.2.0'
    GUID              = 'c7e4a221-9b3f-4d2e-8f10-5a6b7c8d9e0f'
    Author            = 'wbaamaral'
    CompanyName       = 'WBA'
    Copyright         = '(c) 2025 wbaamaral. Todos os direitos reservados.'
    Description       = 'Gerenciamento de itens de inicializacao e servicos de arranque do Windows.'
    PowerShellVersion = '5.1'
    RootModule        = 'WbaToolkit.Startup.psm1'
    RequiredModules   = @(
        @{ ModuleName = 'WbaToolkit.Core'; ModuleVersion = '1.2.0' }
    )
    FunctionsToExport = @(
        'Get-StartupItem'
        'Disable-StartupItem'
        'Enable-StartupItem'
        'Remove-StartupItem'
        'Show-StartupItem'
        'Invoke-StartupManager'
        'Get-ServiceStartupState'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('WBA', 'Windows', 'Startup', 'Inicializacao', 'Servicos')
        }
    }
}
