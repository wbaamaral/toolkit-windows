@{
    RootModule        = 'WbaToolkit.ShadowCopy.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b3c4d5e6-f7a8-9012-b3c4-d5e6f7a89012'
    Author            = 'wbaamaral'
    CompanyName       = 'WBA'
    Copyright         = '(c) 2026 wbaamaral. Todos os direitos reservados.'
    Description       = 'Gerenciamento de Volume Shadow Copy (VSS) e Protecao do Sistema no Windows.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-ShadowCopyProtectionStatus'
        'Enable-SystemProtection'
        'Disable-SystemProtection'
        'New-ShadowCopy'
        'Get-ShadowCopy'
        'Remove-ShadowCopy'
        'Get-ShadowCopyStorage'
        'Set-ShadowCopyStorageLimit'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('VSS', 'ShadowCopy', 'Backup', 'Windows', 'SystemRestore')
            ProjectUri = ''
        }
    }
}
