@{
    ModuleVersion     = '2.0.0'
    GUID              = 'd3f1a8b2-6c4e-4a91-b7d0-2e9f5a1c8b34'
    Author            = 'wbaamaral'
    CompanyName       = 'WBA'
    Copyright         = '(c) 2026 wbaamaral. Todos os direitos reservados.'
    Description       = 'Gerenciamento de identidade e acesso local do Windows. Inclui o logon automatico (autologon) com senha protegida por segredo LSA.'
    PowerShellVersion = '5.1'
    RootModule        = 'WbaToolkit.Identity.psm1'
    RequiredModules   = @(
        @{ ModuleName = 'WbaToolkit.Core'; ModuleVersion = '2.0.0' }
    )
    FunctionsToExport = @(
        'Get-AutologonStatus'
        'Enable-Autologon'
        'Disable-Autologon'
        'Set-Autologon'
        'Invoke-AutologonManager'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('WBA', 'Windows', 'Identity', 'Autologon', 'Login', 'Winlogon')
        }
    }
}
