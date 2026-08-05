function Invoke-ToolkitProvisioningEngine {
    <#
    .SYNOPSIS
        Motor compartilhado por Invoke-ToolkitProvisioning e Resume-ToolkitProvisioning.

    .DESCRIPTION
        Adquire o mutex global, resolve o plano de execucao, percorre as etapas ainda
        nao concluidas persistindo checkpoint atomico apos cada transicao, interrompe
        imediatamente ao pedir reboot (sem tentar a proxima etapa) e finaliza com o
        relatorio sanitizado quando todas as etapas do plano estiverem concluidas.

    .PARAMETER DeploymentId
    .PARAMETER Config
        Configuracao ja validada (objeto convertido de JSON).
    .PARAMETER ConfigHash
    .PARAMETER SchemaVersion
    .PARAMETER ModuleVersion
    .PARAMETER Paths
        Objeto de Get-ToolkitProvisioningPaths.
    .PARAMETER ExistingState
        Estado carregado do disco, quando esta e uma retomada. $null para execucao nova.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: GlobalState, RebootAction, Report (presente somente quando Completed).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentId,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Config,

        [Parameter(Mandatory)]
        [string]$ConfigHash,

        [Parameter(Mandatory)]
        [int]$SchemaVersion,

        [Parameter(Mandatory)]
        [string]$ModuleVersion,

        [Parameter(Mandatory)]
        [pscustomobject]$Paths,

        [AllowNull()]
        [pscustomobject]$ExistingState
    )

    $mutex = Enter-ToolkitProvisioningLock
    try {
        $workDir = Join-Path $Paths.Work $DeploymentId

        if ($ExistingState) {
            if ($ExistingState.ConfigHash -ne $ConfigHash) {
                throw "Hash da configuracao mudou desde a ultima execucao ($($ExistingState.ConfigHash) -> $ConfigHash); execucao interrompida para evitar aplicar documento alterado silenciosamente."
            }
            $state = $ExistingState
        }
        else {
            $state = New-ToolkitProvisioningState -DeploymentId $DeploymentId -ConfigHash $ConfigHash `
                -SchemaVersion $SchemaVersion -ModuleVersion $ModuleVersion
        }

        if ($state.GlobalState -eq 'Completed') {
            return [pscustomobject]@{ GlobalState = 'Completed'; RebootAction = 'None'; Report = $null; AlreadyCompleted = $true }
        }

        $registry     = Get-ToolkitProvisioningStepRegistry
        $plan         = Resolve-ToolkitProvisioningPlan -StepRegistry $registry
        $doneStatuses = @('Compliant', 'Skipped', 'Changed')
        $doneIds      = @($state.StepResults | Where-Object { $doneStatuses -contains $_.Status } | Select-Object -ExpandProperty StepId -Unique)

        $maxAttempts = 3
        $onError     = 'Stop'
        $rebootPolicy = 'WhenRequired'
        if ($Config -and (Test-ToolkitPropertyPresent -InputObject $Config -Name 'policy')) {
            if ((Test-ToolkitPropertyPresent -InputObject $Config.policy -Name 'maxAttemptsPerStep')) { $maxAttempts = [int]$Config.policy.maxAttemptsPerStep }
            if ((Test-ToolkitPropertyPresent -InputObject $Config.policy -Name 'onError')) { $onError = [string]$Config.policy.onError }
            if ((Test-ToolkitPropertyPresent -InputObject $Config.policy -Name 'reboot')) { $rebootPolicy = [string]$Config.policy.reboot }
        }

        $state.GlobalState = 'Running'
        Write-ToolkitProvisioningState -StateDirectory $workDir -State $state

        $context = [pscustomobject]@{
            Config       = $Config
            Paths        = $Paths
            DeploymentId = $DeploymentId
            State        = $state
        }

        foreach ($step in $plan) {
            if ($doneIds -contains $step.Id) {
                continue
            }

            $state.CurrentStepId = $step.Id
            $context.State = $state
            $attempt = 1
            do {
                $result = Invoke-ToolkitProvisioningStep -StepManifest $step -Context $context -Attempt $attempt
                $attempt++
            } while ($result.Status -eq 'Failed' -and $attempt -le $maxAttempts)

            $state.StepResults = @($state.StepResults) + $result
            $state.UpdatedAt   = (Get-Date).ToUniversalTime().ToString('o')

            if ($result.Status -eq 'RebootRequired') {
                $state.GlobalState = 'RebootPending'
                $state.BootCount   = [int]$state.BootCount + 1
                Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
                $rebootOutcome = Request-ToolkitProvisioningReboot -RebootPolicy $rebootPolicy
                return [pscustomobject]@{ GlobalState = 'RebootPending'; RebootAction = $rebootOutcome.Action; Report = $null; AlreadyCompleted = $false }
            }

            if ($result.Status -eq 'Failed') {
                $state.GlobalState = 'Failed'
                Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
                if ($onError -eq 'Stop') {
                    return [pscustomobject]@{ GlobalState = 'Failed'; RebootAction = 'None'; Report = $null; AlreadyCompleted = $false }
                }
                continue
            }

            $state.GlobalState = 'Running'
            Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
        }

        $state.GlobalState   = 'Completed'
        $state.CurrentStepId = $null
        Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
        $report = Complete-ToolkitProvisioning -State $state -Paths $Paths

        return [pscustomobject]@{ GlobalState = 'Completed'; RebootAction = 'None'; Report = $report; AlreadyCompleted = $false }
    }
    finally {
        Exit-ToolkitProvisioningLock -Mutex $mutex
    }
}
