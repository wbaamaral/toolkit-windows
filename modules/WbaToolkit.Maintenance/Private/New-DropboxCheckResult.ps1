# Projeto: wba-toolkit
# Autor: wbaamaral

function New-DropboxCheckResult {
    <#
    .SYNOPSIS
        Cria um objeto de resultado de checagem de saude do Dropbox.

    .DESCRIPTION
        Fabrica compartilhada por todas as funcoes Test-Dropbox* para evitar repetir
        a construcao do pscustomobject de resultado em cada checagem.

    .PARAMETER Categoria
        Categoria da checagem (ex.: 'Processo', 'Rede').

    .PARAMETER Nome
        Nome da checagem.

    .PARAMETER Status
        OK, AVISO, FALHA ou PULADO.

    .PARAMETER Detalhe
        Detalhe textual do resultado.

    .PARAMETER Recomendacao
        Recomendacao para o operador. Opcional.

    .PARAMETER Penalidade
        Pontos subtraidos do score de saude. Padrao 0.

    .PARAMETER Critico
        Marca a checagem como critica quando em FALHA.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Categoria,

        [Parameter(Mandatory = $true)]
        [string]$Nome,

        [Parameter(Mandatory = $true)]
        [ValidateSet('OK', 'AVISO', 'FALHA', 'PULADO')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Detalhe,

        [Parameter(Mandatory = $false)]
        [string]$Recomendacao = '',

        [Parameter(Mandatory = $false)]
        [int]$Penalidade = 0,

        [switch]$Critico
    )

    return [pscustomobject]@{
        Categoria    = $Categoria
        Nome         = $Nome
        Status       = $Status
        Detalhe      = $Detalhe
        Recomendacao = $Recomendacao
        Penalidade   = $Penalidade
        Critico      = [bool]$Critico
    }
}
