function Get-FilesystemErrorEvent {
    <#
    .SYNOPSIS
        Retorna eventos de erro ou falha relacionados ao sistema de arquivos.

    .DESCRIPTION
        Consulta o log de eventos do Sistema buscando erros e falhas criticas nos
        provedores de armazenamento e sistema de arquivos. Retorna array vazio quando
        nenhum evento e encontrado ou quando o log nao esta disponivel.

    .PARAMETER Days
        Numero de dias retroativos a consultar. Padrao: 30.

    .EXAMPLE
        Get-FilesystemErrorEvent

    .EXAMPLE
        Get-FilesystemErrorEvent -Days 7

    .OUTPUTS
        System.Diagnostics.Eventing.Reader.EventLogRecord[]

    .NOTES
        Autor: wbaamaral
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$Days = 30
    )

    $cutoff  = (Get-Date).AddDays(-$Days)
    $sources = @('Ntfs', 'disk', 'volmgr', 'stornvme', 'storahci', 'iaStorAV', 'iaStorAVC', 'partmgr')
    try {
        $found = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 1, 2
            StartTime = $cutoff
        } -ErrorAction Stop | Where-Object { $_.ProviderName -in $sources }
        return $found
    }
    catch {
        if ($_.Exception.Message -notmatch 'No events were found') {
            Write-Warning "Erro ao consultar log do Sistema: $($_.Exception.Message)"
        }
        return @()
    }
}
