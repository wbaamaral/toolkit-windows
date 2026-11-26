function Test-ToolkitCleanupFinalizeDesiredState {
    <#
    .SYNOPSIS
        Etapa cleanup.finalize — verifica se a politica de limpeza ja foi aplicada.

    .DESCRIPTION
        SPEC-PROVISIONING-CONFIG define 'policy.cleanup': RemoveSecretsAndConfig (padrao),
        RemoveSecretsOnly ou RetainAll. Fase 1 nao possui etapas que copiem segredos para
        Secrets\<deploymentId>\ ainda, mas o contrato de limpeza da copia de trabalho da
        configuracao (Work\<deploymentId>\provisioning.json) ja se aplica.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status, Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $policy = 'RemoveSecretsAndConfig'
    if ($Context.Config -and (Test-ToolkitPropertyPresent -InputObject $Context.Config -Name 'policy') -and
        (Test-ToolkitPropertyPresent -InputObject $Context.Config.policy -Name 'cleanup')) {
        $policy = [string]$Context.Config.policy.cleanup
    }

    if ($policy -eq 'RetainAll') {
        return [pscustomobject]@{ Status = 'Compliant'; Message = "Politica 'RetainAll': nada a limpar."; Evidence = [pscustomobject]@{ Policy = $policy } }
    }

    $configCopyPath = Join-Path (Join-Path $Context.Paths.Work $Context.DeploymentId) 'provisioning.json'
    $secretsDir     = Join-Path $Context.Paths.Secrets $Context.DeploymentId

    $configCopyExists = Test-Path -LiteralPath $configCopyPath -PathType Leaf
    $secretsExist     = (Test-Path -LiteralPath $secretsDir) -and (@(Get-ChildItem -LiteralPath $secretsDir -Force -ErrorAction SilentlyContinue).Count -gt 0)

    # Envelopes consumidos: <Secrets>\<secretRef>.cms (SPEC-PROVISIONING-SECURITY, Logs e retencao).
    $remainingEnvelopes = @(
        foreach ($ref in @(Get-ToolkitProvisioningSecretRef -InputObject $Context.Config)) {
            $envelopePath = Join-Path $Context.Paths.Secrets "$ref.cms"
            if (Test-Path -LiteralPath $envelopePath -PathType Leaf) { $envelopePath }
        }
    )

    $mustRemoveConfig = ($policy -eq 'RemoveSecretsAndConfig')

    $pending = ($secretsExist) -or ($remainingEnvelopes.Count -gt 0) -or ($mustRemoveConfig -and $configCopyExists)

    $evidence = [pscustomobject]@{
        Policy             = $policy
        ConfigCopyExists   = $configCopyExists
        SecretsExist       = $secretsExist
        RemainingEnvelopes = $remainingEnvelopes.Count
    }

    if (-not $pending) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'Limpeza ja aplicada.'; Evidence = $evidence }
    }

    return [pscustomobject]@{ Status = 'Changed'; Message = "Limpeza pendente conforme politica '$policy'."; Evidence = $evidence }
}
