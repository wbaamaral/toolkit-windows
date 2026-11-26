function Set-ToolkitCleanupFinalizeDesiredState {
    <#
    .SYNOPSIS
        Etapa cleanup.finalize — aplica a politica de limpeza declarada.

    .DESCRIPTION
        Remove os envelopes <Secrets>\<secretRef>.cms consumidos, a pasta Secrets\<deploymentId>
        e, com 'RemoveSecretsAndConfig', a copia de trabalho da configuracao. 'RetainAll' nao
        remove nada. Caminhos ja ausentes nao geram erro; falha ao remover um caminho existente
        encerra a etapa com erro (segredo nao pode ficar no disco em silencio).
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

    if ($policy -eq 'RetainAll') {
        return [pscustomobject]@{
            RebootRequired = $false
            Message        = "Politica 'RetainAll': nada removido."
            Evidence       = [pscustomobject]@{ Policy = $policy; RemovedPaths = @() }
        }
    }

    $configCopyPath = Join-Path (Join-Path $Context.Paths.Work $Context.DeploymentId) 'provisioning.json'
    $secretsDir     = Join-Path $Context.Paths.Secrets $Context.DeploymentId
    $removed        = New-Object System.Collections.Generic.List[string]
    $failures       = New-Object System.Collections.Generic.List[string]

    # Envelopes consumidos: <Secrets>\<secretRef>.cms (SPEC-PROVISIONING-SECURITY, Logs e retencao).
    $envelopePaths = @(
        foreach ($ref in @(Get-ToolkitProvisioningSecretRef -InputObject $Context.Config)) {
            Join-Path $Context.Paths.Secrets "$ref.cms"
        }
    )

    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($envelopePath in $envelopePaths) {
        $targets.Add([pscustomobject]@{ Path = $envelopePath; Recurse = $false; Action = 'Remover envelope de segredo consumido' })
    }
    $targets.Add([pscustomobject]@{ Path = $secretsDir; Recurse = $true; Action = 'Remover segredos do deployment' })
    if ($policy -eq 'RemoveSecretsAndConfig') {
        $targets.Add([pscustomobject]@{ Path = $configCopyPath; Recurse = $false; Action = 'Remover copia de trabalho da configuracao' })
    }

    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.Path)) { continue }
        if (-not $PSCmdlet.ShouldProcess($target.Path, $target.Action)) { continue }
        try {
            Remove-Item -LiteralPath $target.Path -Recurse:$target.Recurse -Force -ErrorAction Stop
            $removed.Add($target.Path)
        }
        catch {
            $failures.Add(('{0}: {1}' -f $target.Path, $_.Exception.Message))
        }
    }

    if ($failures.Count -gt 0) {
        # Segredo que nao saiu do disco e falha da etapa, nao aviso silencioso.
        throw ("Limpeza incompleta; nao foi possivel remover: {0}" -f ($failures -join '; '))
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Limpeza aplicada conforme politica '$policy'."
        Evidence       = [pscustomobject]@{ Policy = $policy; RemovedPaths = @($removed) }
    }
}
