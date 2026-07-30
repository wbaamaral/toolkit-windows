function Backup-UserData {
    <#
    .SYNOPSIS
        Realiza backup dos dados do usuario.
    .DESCRIPTION
        Faz backup de pastas do perfil do usuario usando rsync.
    .PARAMETER BackupPath
        Caminho de destino do backup. Se omitido, usa o configurado.
    .PARAMETER SourcePaths
        Pastas fonte. Se omitido, usa as configuradas (Documents, Desktop, Pictures).
    .PARAMETER SkipCompression
        Nao comprime o backup em ZIP.
    .OUTPUTS
        Objeto com resultado do backup.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$BackupPath,
        [string[]]$SourcePaths,
        [switch]$SkipCompression
    )

    $store = Get-BackupStorePath -ModuleName 'userdata'

    if (-not $BackupPath) { $BackupPath = $store.Data }
    if (-not $SourcePaths) { $SourcePaths = Resolve-BackupPaths }

    if (-not $SourcePaths -or $SourcePaths.Count -eq 0) {
        throw "Nenhum caminho fonte encontrado para backup."
    }

    $config = Get-BackupConfiguration
    $rsyncPath = 'C:\ProgramData\chocolatey\lib\rsync\tools\rsync.exe'
    if ($config -and $config.UserBackup.RsyncPath) {
        $rsyncPath = [System.Environment]::ExpandEnvironmentVariables($config.UserBackup.RsyncPath)
    }

    if (-not (Test-Path $rsyncPath)) {
        throw "rsync nao encontrado em: $rsyncPath"
    }

    if ($PSCmdlet.ShouldProcess($BackupPath, 'Backup de dados do usuario')) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

        $results = foreach ($source in $SourcePaths) {
            if (-not (Test-Path $source)) { continue }

            $folderName = Split-Path $source -Leaf
            $destFolder = Join-Path $BackupPath $folderName

            Write-BackupLog -Message "Sincronizando: $source -> $destFolder" -Level INFO

            $rsyncArgs = @(
                '-av'
                '--delete'
                '--modify-window=2'
                '--no-perms'
                '--no-owner'
                '--no-group'
                "$source/"
                "$destFolder/"
            )

            try {
                $proc = Start-Process -FilePath $rsyncPath -ArgumentList $rsyncArgs `
                    -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $store.Logs "$folderName-rsync.log") `
                    -RedirectStandardError (Join-Path $store.Logs "$folderName-rsync.err")

                [pscustomobject]@{
                    Source  = $source
                    Dest    = $destFolder
                    ExitCode = $proc.ExitCode
                    Success = ($proc.ExitCode -eq 0)
                }
            } catch {
                [pscustomobject]@{
                    Source  = $source
                    Dest    = $destFolder
                    ExitCode = -1
                    Success = $false
                    Error   = $_.Exception.Message
                }
            }
        }

        $allSuccess = ($results | Where-Object { -not $_.Success }).Count -eq 0

        $meta = [pscustomobject]@{
            BackupPath   = $BackupPath
            SourcePaths  = $SourcePaths
            CreatedAt    = Get-Date
            RsyncPath    = $rsyncPath
            AllSuccess   = $allSuccess
            Results      = $results
        }

        $metaPath = Join-Path $BackupPath 'metadados.json'
        $meta | ConvertTo-Json -Depth 8 | Set-Content -Path $metaPath -Encoding UTF8

        if (-not (Test-Path $store.Logs)) { New-Item -ItemType Directory -Path $store.Logs -Force | Out-Null }
        $meta | ConvertTo-Json -Depth 8 | Set-Content -Path $store.Metadata -Encoding UTF8

        if ($allSuccess) {
            Write-BackupLog -Message "Backup concluido com sucesso: $BackupPath" -Level OK
        } else {
            Write-BackupLog -Message "Backup concluido com erros. Verifique os logs." -Level WARN
        }

        $meta
    }
}
