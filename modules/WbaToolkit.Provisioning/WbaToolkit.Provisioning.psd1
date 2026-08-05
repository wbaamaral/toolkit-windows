@{
    ModuleVersion     = '0.1.0'
    GUID              = 'a1c4e9d2-7b3f-4d6a-9e8c-5f2b1a9d4c7e'
    Author            = 'wbaamaral'
    CompanyName       = 'WBA'
    Copyright         = '(c) 2026 wbaamaral. Todos os direitos reservados.'
    Description       = 'Motor declarativo de provisionamento inicial (primeiro boot) do Windows. Fase 1: nucleo seguro — validacao de configuracao, planejador, estado atomico, tarefa agendada e etapas de identidade/finalizacao.'
    PowerShellVersion = '5.1'
    RootModule        = 'WbaToolkit.Provisioning.psm1'
    RequiredModules   = @(
        @{ ModuleName = 'WbaToolkit.Core'; ModuleVersion = '1.0.0' }
    )
    FunctionsToExport = @(
        'Install-ToolkitProvisioning'
        'Uninstall-ToolkitProvisioning'
        'Enable-ToolkitProvisioning'
        'Disable-ToolkitProvisioning'
        'Test-ToolkitProvisioningConfig'
        'Get-ToolkitProvisioningConfig'
        'Get-ToolkitProvisioningState'
        'Reset-ToolkitProvisioningState'
        'Invoke-ToolkitProvisioning'
        'Resume-ToolkitProvisioning'
        'Get-ToolkitProvisioningResult'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('WBA', 'Windows', 'Provisioning', 'FirstBoot', 'Declarative')
        }
    }
}
