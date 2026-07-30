function Remove-BackupAntigo {
    <#
    .SYNOPSIS
        Remove backups antigos por retencao.
    .DESCRIPTION
        Remove diretorios de backup mais antigos que o periodo especificado.
    .PARAMETER Days
        Dias de retencao. Backups mais antigos serao removidos.
    .PARAMETER BackupRoot
        Diretorio raiz dos backups. Se omitido, usa o configurado.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [int]$Days,

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

    if (-not (Test-Path $BackupRoot)) { Write-Warning "Diretorio de backups nao encontrado: $BackupRoot"; return }

    $cutoff = (Get-Date).AddDays(-$Days)
    $oldBackups = Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $metaPath = Join-Path $_.FullName 'metadados.json'
            if (Test-Path $metaPath) {
                try {
                    $meta = Get-Content -Path $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $createdAt = [datetime]$meta.CreatedAt
                    $createdAt -lt $cutoff
                } catch { $false }
            } else {
                $_.CreationTime -lt $cutoff
            }
        }

    if (-not $oldBackups) { Write-Output "Nenhum backup antigo encontrado (>$Days dias)."; return }

    $count = ($oldBackups | Measure-Object).Count
    if ($PSCmdlet.ShouldProcess("$count backup(s) antigo(s)", 'Remover')) {
        $oldBackups | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "$count backup(s) antigo(s) removido(s)."
    }
}
