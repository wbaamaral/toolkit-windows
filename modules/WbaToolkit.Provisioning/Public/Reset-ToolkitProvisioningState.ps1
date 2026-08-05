function Reset-ToolkitProvisioningState {
    <#
    .SYNOPSIS
        Permite reexecutar um deployment ja concluido ou travado em falha terminal.

    .DESCRIPTION
        SPEC-PROVISIONING-ENGINE: um deploymentId concluido nao executa novamente sem
        esta funcao, e reset nao remove evidencias por padrao — apenas reescreve
        state.json com GlobalState 'Planned' e zera os resultados de etapa, preservando
        state.previous.json e os relatorios ja gerados em Results\. Operacao de alto
        impacto: exige confirmacao.

    .PARAMETER DeploymentId
        Identificador do deployment.

    .PARAMETER RemoveEvidence
        Alem de resetar o estado, remove tambem os relatorios anteriores em
        Results\<deploymentId>\. Destrutivo.

    .EXAMPLE
        Reset-ToolkitProvisioningState -DeploymentId 'filial-pvh-estacao-018' -Confirm:$false

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentId,

        [switch]$RemoveEvidence
    )

    $paths = Get-ToolkitProvisioningPaths
    $stateDirectory = Join-Path $paths.Work $DeploymentId
    $current = Read-ToolkitProvisioningState -StateDirectory $stateDirectory

    if (-not $current.Found -or $null -eq $current.State) {
        throw "Nenhum estado encontrado para o deployment '$DeploymentId'; nada a resetar."
    }

    if (-not $PSCmdlet.ShouldProcess($DeploymentId, 'Resetar estado de provisionamento para nova execucao')) {
        return [pscustomobject]@{ Success = $false; Message = 'Operacao cancelada (WhatIf).' }
    }

    $resetState = $current.State
    $resetState.GlobalState   = 'Planned'
    $resetState.CurrentStepId = $null
    $resetState.StepResults   = @()
    $resetState.UpdatedAt     = (Get-Date).ToUniversalTime().ToString('o')

    Write-ToolkitProvisioningState -StateDirectory $stateDirectory -State $resetState

    if ($RemoveEvidence) {
        $resultDir = Join-Path $paths.Results $DeploymentId
        if (Test-Path -LiteralPath $resultDir) {
            Remove-Item -LiteralPath $resultDir -Recurse -Force
        }
    }

    [pscustomobject]@{
        Success = $true
        Message = "Estado de '$DeploymentId' resetado para 'Planned'. Evidencias " + $(if ($RemoveEvidence) { 'removidas.' } else { 'preservadas.' })
    }
}
