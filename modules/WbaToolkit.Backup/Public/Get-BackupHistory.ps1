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

    $metaFiles | ForEach-Object {
        try {
            $meta = Get-Content -Path $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            [pscustomobject]@{
                BackupPath  = $meta.BackupPath
                CreatedAt   = $meta.CreatedAt
                AllSuccess  = $meta.AllSuccess
                SourceCount = if ($meta.SourcePaths) { $meta.SourcePaths.Count } else { 0 }
                Folder      = $_.DirectoryName
            }
        } catch { Write-Verbose "Metadados de backup invalidos em '$($_.FullName)' foram ignorados: $($_.Exception.Message)" }
    } | Sort-Object CreatedAt -Descending
}
