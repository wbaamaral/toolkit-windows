@{
    RootModule        = 'WbaToolkit.Backup.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd5e6f7a8-9012-3456-d5e6-f7a890123456'
    Author            = 'wbaamaral'
    CompanyName       = 'WBA'
    Copyright         = '(c) 2026 wbaamaral. Todos os direitos reservados.'
    Description       = 'Gerenciamento de pontos de restauracao, backup de dados do usuario e ciclo de copias.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-RestorePointInfo'
        'New-RestorePoint'
        'Remove-RestorePoint'
        'Restore-SystemToPoint'
        'Backup-UserData'
        'Restore-UserData'
        'Get-BackupHistory'
        'Remove-BackupAntigo'
        'Test-VssHealth'
        'Get-BackupConfiguration'
        'Set-BackupConfiguration'
        'Export-BackupReport'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Backup', 'RestorePoint', 'SystemRestore', 'UserBackup', 'rsync', 'VSS')
            ProjectUri = ''
        }
    }
}
