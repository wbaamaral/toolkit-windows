function Set-ToolkitCleanupFinalizeDesiredState {
    <#
    .SYNOPSIS
        Etapa cleanup.finalize — aplica a politica de limpeza declarada.

    .DESCRIPTION
        Remove a copia de trabalho da configuracao e/ou os segredos do deployment
        conforme 'policy.cleanup'. Best-effort: caminhos ja ausentes nao geram erro.
        Nunca remove state.json ou o relatorio em Results\ — apenas a copia de
        configuracao e segredos, que sao os artefatos sensiveis desta fase.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $policy = 'RemoveSecretsAndConfig'
    if ($Context.Config -and (Test-ToolkitPropertyPresent -InputObject $Context.Config -Name 'policy') -and
        (Test-ToolkitPropertyPresent -InputObject $Context.Config.policy -Name 'cleanup')) {
        $policy = [string]$Context.Config.policy.cleanup
    }

    $configCopyPath = Join-Path (Join-Path $Context.Paths.Work $Context.DeploymentId) 'provisioning.json'
    $secretsDir     = Join-Path $Context.Paths.Secrets $Context.DeploymentId
    $removed        = New-Object System.Collections.Generic.List[string]

    if ((Test-Path -LiteralPath $secretsDir) -and $PSCmdlet.ShouldProcess($secretsDir, 'Remover segredos do deployment')) {
        Remove-Item -LiteralPath $secretsDir -Recurse -Force -ErrorAction SilentlyContinue
        $removed.Add($secretsDir)
    }

    if ($policy -eq 'RemoveSecretsAndConfig' -and (Test-Path -LiteralPath $configCopyPath -PathType Leaf) -and
        $PSCmdlet.ShouldProcess($configCopyPath, 'Remover copia de trabalho da configuracao')) {
        Remove-Item -LiteralPath $configCopyPath -Force -ErrorAction SilentlyContinue
        $removed.Add($configCopyPath)
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Limpeza aplicada conforme politica '$policy'."
        Evidence       = [pscustomobject]@{ Policy = $policy; RemovedPaths = @($removed) }
    }
}
