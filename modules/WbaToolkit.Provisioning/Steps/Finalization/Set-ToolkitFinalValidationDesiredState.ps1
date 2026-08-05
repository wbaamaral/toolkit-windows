function Set-ToolkitFinalValidationDesiredState {
    <#
    .SYNOPSIS
        Etapa validation.final — Set intencionalmente inatingivel.

    .DESCRIPTION
        Assim como preflight.system, validation.final so avalia; nunca converge nada por
        si mesma. ponytail: presente por contrato, sem logica de convergencia.

    .PARAMETER Context
        Nao utilizado.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    if ($PSCmdlet.ShouldProcess('validation.final', 'Nenhuma acao (etapa de avaliacao)')) {
        # Nada a convergir.
    }

    [pscustomobject]@{ RebootRequired = $false; Message = 'validation.final nao possui acao de convergencia.'; Evidence = $null }
}
