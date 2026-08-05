function Resume-ToolkitProvisioning {
    <#
    .SYNOPSIS
        Retoma um deployment existente a partir do checkpoint persistido.

    .DESCRIPTION
        Usado pela tarefa agendada apos cada reinicializacao: le state.json e
        provisioning.json da area de trabalho e continua exatamente da etapa pendente,
        sem repetir etapas ja verificadas (SPEC-PROVISIONING-ENGINE). Estado em 'Failed'
        so e retomado com -Force, conforme a maquina de estados ('Failed -> Running
        somente por retomada explicita e politica valida').

    .PARAMETER DeploymentId
        Identificador do deployment a retomar.

    .PARAMETER Force
        Permite retomar um deployment que esta em estado 'Failed'.

    .EXAMPLE
        Resume-ToolkitProvisioning -DeploymentId 'filial-pvh-estacao-018'

    .OUTPUTS
        System.Management.Automation.PSCustomObject — GlobalState, RebootAction, Report.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentId,

        [switch]$Force
    )

    $paths   = Get-ToolkitProvisioningPaths
    $workDir = Join-Path $paths.Work $DeploymentId

    $existing = Read-ToolkitProvisioningState -StateDirectory $workDir
    if (-not $existing.Found -or $null -eq $existing.State) {
        throw "Nenhum estado encontrado para o deployment '$DeploymentId'; nao ha o que retomar. Use Invoke-ToolkitProvisioning."
    }

    if ($existing.State.GlobalState -eq 'Failed' -and -not $Force) {
        throw "Deployment '$DeploymentId' esta em estado 'Failed'. Retome com -Force apos corrigir a causa, ou use Reset-ToolkitProvisioningState."
    }

    if ($existing.State.GlobalState -eq 'Completed') {
        return [pscustomobject]@{ GlobalState = 'Completed'; RebootAction = 'None'; Report = (Get-ToolkitProvisioningResult -DeploymentId $DeploymentId) }
    }

    $configPath = Join-Path $workDir 'provisioning.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Copia de trabalho da configuracao nao encontrada para retomar '$DeploymentId': $configPath"
    }
    $imported = Import-ToolkitProvisioningConfig -Path $configPath

    if (-not $PSCmdlet.ShouldProcess($DeploymentId, 'Retomar provisionamento')) {
        return [pscustomobject]@{ GlobalState = $existing.State.GlobalState; RebootAction = 'None'; Report = $null }
    }

    $moduleVersion = $(if ($module = Get-Module -Name 'WbaToolkit.Provisioning') { $module.Version.ToString() } else { '0.0.0' })

    Invoke-ToolkitProvisioningEngine -DeploymentId $DeploymentId -Config $imported.Config -ConfigHash $imported.Sha256 `
        -SchemaVersion ([int]$imported.Config.schemaVersion) -ModuleVersion $moduleVersion `
        -Paths $paths -ExistingState $existing.State
}
