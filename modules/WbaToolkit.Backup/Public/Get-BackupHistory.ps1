function Get-BackupHistory {
    <#
    .SYNOPSIS
        Retorna historico de backups realizados.
    .DESCRIPTION
        Lista backups anteriores a partir dos metadados.json encontrados.
    .PARAMETER BackupRoot
        Diretorio raiz dos backups. Se omitido, usa o configurado.
    .OUTPUTS
        Lista de PSCustomObject.
    #>
    [CmdletBinding()]
    param(
        [string]$BackupRoot
    )

    if (-not $BackupRoot) {
        $config = Get-BackupConfiguration
        if ($config -and $config.UserBackup.LocalBackupPath) {
            $BackupRoot = [System.Environment]::ExpandEnvironmentVariables($config.UserBackup.LocalBackupPath)
        } else {
            $BackupRoot = 'C:\WBA\Backups'
        }
    }

    if (-not (Test-Path $BackupRoot)) { return @() }

    $metaFiles = Get-ChildItem -Path $BackupRoot -Recurse -Filter 'metadados.json' -ErrorAction SilentlyContinue

    $entries = foreach ($metaFile in $metaFiles) {
        try {
            $meta = Get-Content -Path $metaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            [pscustomobject]@{
                BackupPath  = $meta.BackupPath
                CreatedAt   = ConvertFrom-BackupCreatedAt -Value $meta.CreatedAt
                AllSuccess  = $meta.AllSuccess
                SourceCount = if ($meta.SourcePaths) { @($meta.SourcePaths).Count } else { 0 }
                Folder      = $metaFile.DirectoryName
            }
        } catch { Write-Verbose "Metadados de backup invalidos em '$($metaFile.FullName)' foram ignorados: $($_.Exception.Message)" }
    }

    # Backup-UserData grava o mesmo metadados.json na sessao e em <sessao>\data:
    # agrupa por backup (caminho + data) e mantem a entrada da pasta mais externa.
    $entries |
        Group-Object { '{0}|{1}' -f $_.BackupPath, $(if ($_.CreatedAt) { $_.CreatedAt.Ticks } else { $_.Folder }) } |
        ForEach-Object { $_.Group | Sort-Object { $_.Folder.Length } | Select-Object -First 1 } |
        Sort-Object CreatedAt -Descending
}
