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
    "<nome>.backup" neste diretório; se já existir um backup com esse nome
    (arquivo homônimo de outra pasta), usa "<nome>.<n>.backup". Um backup
    existente nunca é sobrescrito.

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

        # Arquivos de pastas diferentes podem ter o mesmo nome: nunca sobrescrever um
        # backup existente. Usa '<nome>.<n>.backup' a partir da segunda ocorrencia.
        $counter = 1
        while (Test-Path -LiteralPath $backupPath) {
            $counter++
            $backupPath = Join-Path $BackupDir "$fileName.$counter.backup"
        }

        # Criar backup (sem -Force: falha em vez de sobrescrever em caso de corrida)
        Copy-Item -LiteralPath $Path -Destination $backupPath -ErrorAction Stop
        Write-Debug "Criado backup: $backupPath"
        return $true
    }
    catch {
        Write-Warn "Nao foi possivel criar backup de '$Path': $($_.Exception.Message)"
        return $false
    }
}
