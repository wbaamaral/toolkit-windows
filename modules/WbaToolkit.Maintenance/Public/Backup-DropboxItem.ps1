#Requires -Version 5.1
<#
.SYNOPSIS
    Cria backup de um arquivo antes de operações destrutivas.

.DESCRIPTION
    Copia o arquivo especificado para o diretório de backup antes de
    operações de renomeação ou movimentação. Retorna $true se o backup
    foi criado com sucesso, $false caso contrário.

.PARAMETER Path
    Caminho completo do arquivo a ser copiado.

.PARAMETER BackupDir
    Diretório de destino do backup. O arquivo será salvo como
    "<nome>.backup" neste diretório.

.EXAMPLE
    Backup-DropboxItem -Path 'C:\Dropbox\arquivo.txt' -BackupDir 'C:\WBA\backups'

.EXAMPLE
    if (-not (Backup-DropboxItem -Path $arquivo -BackupDir $backupDir)) {
        throw "Backup falhou"
    }

.OUTPUTS
    System.Boolean
    $true se backup criado com sucesso, $false caso contrário.
#>
function Backup-DropboxItem {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$BackupDir
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    try {
        $fileName = Split-Path -Leaf $Path
        $backupPath = Join-Path $BackupDir "$fileName.backup"

        # Criar backup
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        Write-Debug "Criado backup: $backupPath"
        return $true
    }
    catch {
        Write-Warn "Nao foi possivel criar backup de '$Path': $($_.Exception.Message)"
        return $false
    }
}
