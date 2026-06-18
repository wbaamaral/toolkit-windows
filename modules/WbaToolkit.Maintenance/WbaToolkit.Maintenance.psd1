@{
    ModuleVersion     = '1.2.0'
    GUID              = 'd5e3f178-2a4c-4e8b-b9c1-7e2a5d6f0891'
    Author            = 'wbaamaral'
    CompanyName       = 'WBA'
    Copyright         = '(c) 2025 wbaamaral. Todos os direitos reservados.'
    Description       = 'Preparacao de imagem e manutencao avancada do Windows.'
    PowerShellVersion = '5.1'
    RootModule        = 'WbaToolkit.Maintenance.psm1'
    RequiredModules   = @(
        @{ ModuleName = 'WbaToolkit.Core'; ModuleVersion = '1.1.0' }
    )
    FunctionsToExport = @(
        'Get-DefaultUserHivePath'
        'Invoke-WithDefaultUserHive'
        'Import-RegistryTweakToDefaultProfile'
        'Test-SysprepEnvironment'
        'Invoke-SysprepPreparation'
        'Remove-SafePath'
        'Get-DiskInfo'
        'Get-FilesystemErrorEvent'
        'Write-MaintenanceEvent'
        'Invoke-FilesystemCheck'
        'Invoke-EventLogMaintenance'
        'Get-ComponentStoreInfo'
        'Invoke-ComponentStoreCleanup'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('WBA', 'Windows', 'Sysprep', 'Imagem', 'Manutencao')
        }
    }
}
