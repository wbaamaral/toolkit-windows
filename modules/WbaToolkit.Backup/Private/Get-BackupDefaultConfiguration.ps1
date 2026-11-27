function Get-BackupDefaultConfiguration {
    # Valores padrao da configuracao de backup, independentes de qualquer arquivo.
    # Usado por Get-BackupConfiguration (sem arquivo) e por Set-BackupConfiguration -Reset.
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        RestorePoints = [pscustomobject]@{
            MaxRestorePoints = 10
            MinDiskSpaceGB   = 10
            RetentionDays    = 30
            Description      = 'WBA Toolkit Restore Point'
        }
        UserBackup = [pscustomobject]@{
            BackupPaths       = @(
                "$env:USERPROFILE\Documents",
                "$env:USERPROFILE\Desktop",
                "$env:USERPROFILE\Pictures"
            )
            LocalBackupPath   = 'C:\WBA\Backups'
            RsyncPath         = 'C:\ProgramData\chocolatey\lib\rsync\tools\rsync.exe'
            CompressionEnabled = $true
            RetentionDays     = 90
            ExclusionPatterns = @('*.tmp', '*.log', 'Thumbs.db')
        }
    }
}
