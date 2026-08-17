# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxProcesso {
    <#
    .SYNOPSIS
        Checagem de saude: processo dropbox.exe em execucao.

    .DESCRIPTION
        FALHA critica se nenhuma instancia estiver em execucao. AVISO se houver
        mais de uma instancia (incomum).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param()

    $processes = @(Get-DropboxProcessInfo)

    if ($processes.Count -eq 0) {
        return New-DropboxCheckResult -Categoria 'Processo' -Nome 'Processo dropbox.exe' -Status 'FALHA' `
            -Detalhe 'Nenhuma instancia do processo Dropbox esta em execucao.' `
            -Recomendacao 'Inicie o cliente Dropbox ou use -ReiniciarProcesso em modo Assistido.' `
            -Penalidade 40 -Critico
    }

    if ($processes.Count -gt 1) {
        return New-DropboxCheckResult -Categoria 'Processo' -Nome 'Processo dropbox.exe' -Status 'AVISO' `
            -Detalhe "Foram encontradas $($processes.Count) instancias do processo Dropbox, o que e incomum." `
            -Recomendacao 'Considere reiniciar o cliente para eliminar instancias duplicadas.' `
            -Penalidade 10
    }

    return New-DropboxCheckResult -Categoria 'Processo' -Nome 'Processo dropbox.exe' -Status 'OK' `
        -Detalhe 'Processo Dropbox em execucao (1 instancia).'
}
