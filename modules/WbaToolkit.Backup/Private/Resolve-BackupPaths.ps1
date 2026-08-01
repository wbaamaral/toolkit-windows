function Resolve-BackupPaths {
    [CmdletBinding()]
    param()

    $configPath = Get-BackupConfigurationInternal
    $defaultPaths = @(
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Pictures"
    )

    if ($configPath -and (Test-Path $configPath)) {
        try {
            $cfg = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.UserBackup.BackupPaths -and $cfg.UserBackup.BackupPaths.Count -gt 0) {
                $defaultPaths = $cfg.UserBackup.BackupPaths | ForEach-Object {
                    [System.Environment]::ExpandEnvironmentVariables($_)
                }
            }
        } catch { Write-Verbose "Nao foi possivel ler '$configPath'; usando os caminhos de backup padrao. $($_.Exception.Message)" }
    }

    $defaultPaths | Where-Object { Test-Path $_ }
}
