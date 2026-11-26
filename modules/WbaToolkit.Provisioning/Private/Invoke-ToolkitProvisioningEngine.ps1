function Invoke-ToolkitProvisioningEngine {
    <#
    .SYNOPSIS
        Motor compartilhado por Invoke-ToolkitProvisioning e Resume-ToolkitProvisioning.

    .DESCRIPTION
        Adquire o mutex global, resolve o plano de execucao, percorre as etapas ainda
        nao concluidas persistindo checkpoint atomico apos cada transicao, interrompe
        imediatamente ao pedir reboot (sem tentar a proxima etapa) e finaliza com o
        relatorio sanitizado quando todas as etapas do plano estiverem concluidas.

        Estados terminais: Completed so quando nenhuma etapa falhou. Falha com onError=Stop,
        etapas falhas com onError=Continue ou limite de 10 boots atingido terminam em Failed;
        em ambos os casos o relatorio e gravado e a tarefa de boot e desabilitada, exigindo
        retomada explicita (Failed -> Running).

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
    [CmdletBinding()]
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

        # Limite de boots do deployment: evita loop de reinicializacao quando uma etapa
        # pede reboot indefinidamente (SPEC-PROVISIONING-EXECUTION, Concorrencia e repeticao).
        $maxBoots = 10
        $failedStepIds = New-Object System.Collections.Generic.List[string]

        # Estado terminal (Completed ou Failed): persiste, gera relatorio e desabilita a tarefa
        # de boot (Complete-ToolkitProvisioning), para que uma falha nao se repita a cada boot.
        $finishTerminal = {
            param([string]$GlobalState, [string]$Reason)
            $state.GlobalState   = $GlobalState
            $state.CurrentStepId = $null
            $state.UpdatedAt     = (Get-Date).ToUniversalTime().ToString('o')
            Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
            $finalReport = Complete-ToolkitProvisioning -State $state -Paths $Paths
            [pscustomobject]@{
                GlobalState      = $GlobalState
                RebootAction     = 'None'
                Report           = $finalReport
                AlreadyCompleted = $false
                FailureReason    = $Reason
            }
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
                if ([int]$state.BootCount -ge $maxBoots) {
                    # Limite de boots (SPEC-PROVISIONING-EXECUTION): falha terminal em vez de loop de reinicializacao.
                    Write-Warning "Etapa '$($step.Id)' pediu reboot apos $($state.BootCount) boots (limite $maxBoots); provisionamento encerrado em Failed."
                    return (& $finishTerminal 'Failed' "Limite de $maxBoots boots atingido na etapa '$($step.Id)'.")
                }
                $state.GlobalState = 'RebootPending'
                $state.BootCount   = [int]$state.BootCount + 1
                Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
                $rebootOutcome = Request-ToolkitProvisioningReboot -RebootPolicy $rebootPolicy
                return [pscustomobject]@{ GlobalState = 'RebootPending'; RebootAction = $rebootOutcome.Action; Report = $null; AlreadyCompleted = $false }
            }

            if ($result.Status -eq 'Failed') {
                $failedStepIds.Add($step.Id)
                if ($onError -eq 'Stop') {
                    return (& $finishTerminal 'Failed' "Etapa '$($step.Id)' falhou (onError=Stop).")
                }
                # onError=Continue: segue para as proximas etapas, mas o deployment nao termina Completed.
                Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
                continue
            }

            $state.GlobalState = 'Running'
            Write-ToolkitProvisioningState -StateDirectory $workDir -State $state
        }

        if ($failedStepIds.Count -gt 0) {
            return (& $finishTerminal 'Failed' ("Etapas com falha (onError=Continue): {0}." -f ($failedStepIds -join ', ')))
        }

        return (& $finishTerminal 'Completed' $null)
    }
    finally {
        Exit-ToolkitProvisioningLock -Mutex $mutex
    }
}
