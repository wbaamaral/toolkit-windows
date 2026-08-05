function Set-ToolkitPreflightDesiredState {
    <#
    .SYNOPSIS
        Etapa preflight.system — Set intencionalmente inatingivel.

    .DESCRIPTION
        preflight.system e uma etapa de avaliacao pura: Test-ToolkitPreflightDesiredState
        so devolve 'Compliant' ou 'Failed', nunca 'Changed' — o executor nunca chama esta
        funcao em operacao normal. Existe apenas para satisfazer o contrato do manifesto
        (Test/Set/Verify). ponytail: presente por contrato, sem logica de convergencia.

    .PARAMETER Context
        Nao utilizado.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    if ($PSCmdlet.ShouldProcess('preflight.system', 'Nenhuma acao (etapa de avaliacao)')) {
        # Nada a convergir.
    }

    [pscustomobject]@{ RebootRequired = $false; Message = 'preflight.system nao possui acao de convergencia.'; Evidence = $null }
}
