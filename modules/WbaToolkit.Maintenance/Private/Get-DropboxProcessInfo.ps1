# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxProcessInfo {
    <#
    .SYNOPSIS
        Retorna as instancias em execucao do processo do cliente Dropbox.

    .DESCRIPTION
        Fronteira isolada e mockavel sobre Get-Process. Ausencia do processo e um
        cenario esperado (cliente parado) e retorna array vazio em vez de lancar.

    .OUTPUTS
        System.Diagnostics.Process[]
    #>
    [CmdletBinding()]
    param()

    try {
        return @(Get-Process -Name 'Dropbox' -ErrorAction Stop)
    }
    catch {
        Write-Verbose "Processo Dropbox nao encontrado em execucao: $($_.Exception.Message)"
        return @()
    }
}
