# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxArquivosProblema {
    <#
    .SYNOPSIS
        Checagem de saude: arquivos/pastas com nome ou caminho problematico.

    .DESCRIPTION
        Usa os ProblemFlags anexados por Get-DropboxFileReport. Nunca critica --
        um item com nome problematico nao trava o resto da sincronizacao.

    .PARAMETER FileReport
        Resultado de Get-DropboxFileReport (com a coluna ProblemFlags).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$FileReport = @()
    )

    $withFlags = @($FileReport | Where-Object { $_.ProblemFlags -and @($_.ProblemFlags).Count -gt 0 })

    if ($withFlags.Count -eq 0) {
        return New-DropboxCheckResult -Categoria 'Arquivos' -Nome 'Nomes/caminhos problematicos' -Status 'OK' `
            -Detalhe 'Nenhum arquivo com nome ou caminho problematico foi encontrado.'
    }

    $examples = @($withFlags | Select-Object -First 5 | ForEach-Object {
        "$($_.Caminho) ($(($_.ProblemFlags) -join '; '))"
    })

    return New-DropboxCheckResult -Categoria 'Arquivos' -Nome 'Nomes/caminhos problematicos' -Status 'AVISO' `
        -Detalhe "Foram encontrados $($withFlags.Count) item(ns) com nome/caminho problematico. Exemplos: $($examples -join ' | ')" `
        -Recomendacao 'Renomeie ou mova esses itens para evitar falhas de sincronizacao.' `
        -Penalidade 10
}
