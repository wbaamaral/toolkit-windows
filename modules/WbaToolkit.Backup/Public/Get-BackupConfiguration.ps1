function Get-BackupConfiguration {
    <#
    .SYNOPSIS
        Retorna a configuracao atual de backup.
    .DESCRIPTION
        Le o arquivo config-backup.json e retorna como objeto.
    .OUTPUTS
        PSCustomObject com configuracao de backup.
    #>
    [CmdletBinding()]
    param()

    $configPath = Get-BackupConfigurationInternal

    if (-not $configPath -or -not (Test-Path $configPath)) {
        Write-Warning "Arquivo config-backup.json nao encontrado. Usando valores padrao."
        return [pscustomobject]@{
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

    Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
