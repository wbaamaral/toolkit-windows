function Restore-UserData {
    <#
    .SYNOPSIS
        Restaura dados do usuario a partir de um backup.
    .DESCRIPTION
        Restaura pastas do perfil do usuario usando rsync.
    .PARAMETER BackupPath
        Caminho do backup a restaurar.
    .PARAMETER TargetPath
        Caminho de destino. Se omitido, usa o perfil do usuario atual.
    .OUTPUTS
        Objeto com resultado da restauracao.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,

        [string]$TargetPath
    )

    if (-not (Test-Path $BackupPath)) { throw "Caminho de backup nao encontrado: $BackupPath" }

    $metaPath = Join-Path $BackupPath 'metadados.json'
    if (-not (Test-Path $metaPath)) { throw "metadados.json nao encontrado no backup." }

    $meta = Get-Content -Path $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not $TargetPath) { $TargetPath = $env:USERPROFILE }

    $config = Get-BackupConfiguration
    $rsyncPath = 'C:\ProgramData\chocolatey\lib\rsync\tools\rsync.exe'
    if ($config -and $config.UserBackup.RsyncPath) {
        $rsyncPath = [System.Environment]::ExpandEnvironmentVariables($config.UserBackup.RsyncPath)
    }

    if ($PSCmdlet.ShouldProcess($TargetPath, 'Restaurar dados do usuario')) {
        $backupFolders = Get-ChildItem -Path $BackupPath -Directory -ErrorAction SilentlyContinue

        $results = foreach ($folder in $backupFolders) {
            $destFolder = Join-Path $TargetPath $folder.Name
            $sourcePath = Join-Path $folder.FullName ''

            Write-BackupLog -Message "Restaurando: $($folder.FullName) -> $destFolder" -Level INFO

            $rsyncArgs = @(
                '-av'
                "$sourcePath/"
                "$destFolder/"
            )

            try {
                $proc = Start-Process -FilePath $rsyncPath -ArgumentList $rsyncArgs `
                    -NoNewWindow -Wait -PassThru

                [pscustomobject]@{
                    Source   = $folder.FullName
                    Dest     = $destFolder
                    ExitCode = $proc.ExitCode
                    Success  = ($proc.ExitCode -eq 0)
                }
            } catch {
                [pscustomobject]@{
                    Source   = $folder.FullName
                    Dest     = $destFolder
                    ExitCode = -1
                    Success  = $false
                    Error    = $_.Exception.Message
                }
            }
        }

        $allSuccess = ($results | Where-Object { -not $_.Success }).Count -eq 0

        if ($allSuccess) {
            Write-BackupLog -Message "Restauracao concluida com sucesso." -Level OK
        } else {
            Write-BackupLog -Message "Restauracao concluida com erros." -Level WARN
        }

        [pscustomobject]@{
            BackupPath = $BackupPath
            TargetPath = $TargetPath
            AllSuccess = $allSuccess
            Results    = $results
        }
    }
}
