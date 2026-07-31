function Get-BackupStorePath {
    [CmdletBinding()]
    param(
        [string]$ModuleName = 'backup'
    )

    $configPath = Get-BackupConfigurationInternal
    $backupRoot = 'C:\WBA\Backups'

    if ($configPath -and (Test-Path $configPath)) {
        try {
            $cfg = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.UserBackup.LocalBackupPath) {
                $backupRoot = [System.Environment]::ExpandEnvironmentVariables($cfg.UserBackup.LocalBackupPath)
            }
        } catch { }
    }

    $timestamp = Get-Date -Format 'ddMMyyyy_HHmmss'
    $sessionPath = Join-Path $backupRoot "$ModuleName\$timestamp"

    @{
        Root     = $backupRoot
        Session  = $sessionPath
        Logs     = Join-Path $sessionPath 'logs'
        Data     = Join-Path $sessionPath 'data'
        Metadata = Join-Path $sessionPath 'metadados.json'
    }
}
