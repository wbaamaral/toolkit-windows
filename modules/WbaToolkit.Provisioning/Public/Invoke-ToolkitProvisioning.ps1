function Invoke-ToolkitProvisioning {
    <#
    .SYNOPSIS
        Inicia (ou continua) o provisionamento a partir de uma configuracao valida.

    .DESCRIPTION
        Fluxo completo de SPEC-PROVISIONING-VISAO: localiza a configuracao, valida schema
        e semantica, copia para a area de trabalho protegida com hash SHA-256, resolve o
        plano de etapas e executa ate concluir, falhar ou pedir reboot. Configuracao
        invalida nunca chega a alterar o sistema — a validacao ocorre antes de qualquer
        copia ou execucao. Se ja existir um deployment com o mesmo Id concluido, recusa
        reexecutar (usar Reset-ToolkitProvisioningState).

    .PARAMETER ConfigPath
        Caminho explicito da configuracao. Quando omitido, usa a precedencia padrao
        (Inbox, midia removivel).

    .EXAMPLE
        Invoke-ToolkitProvisioning -ConfigPath C:\WBA\provisioning.json

    .EXAMPLE
        Invoke-ToolkitProvisioning -WhatIf

        Mostra o plano completo sem alterar o sistema.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — GlobalState, RebootAction, Report.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ConfigPath
    )

    $paths = Get-ToolkitProvisioningPaths
    $resolvedPath = Find-ToolkitProvisioningConfig -ConfigPath $ConfigPath -Paths $paths
    $imported     = Import-ToolkitProvisioningConfig -Path $resolvedPath
    $validation   = Test-ToolkitProvisioningSchema -Config $imported.Config

    if (-not $validation.IsValid) {
        throw "Configuracao invalida em '$resolvedPath'; nenhuma alteracao foi feita no sistema. Erros: $($validation.Errors -join ' | ')"
    }

    $deploymentId = [string]$imported.Config.deploymentId
    $workDir      = Join-Path $paths.Work $deploymentId

    $existing = Read-ToolkitProvisioningState -StateDirectory $workDir
    if ($existing.Found -and $existing.State -and $existing.State.GlobalState -eq 'Completed') {
        throw "Deployment '$deploymentId' ja esta concluido. Use Reset-ToolkitProvisioningState para reexecutar."
    }
    if ($existing.Found -and $existing.State -and $existing.State.GlobalState -eq 'Failed') {
        throw "Deployment '$deploymentId' esta em estado 'Failed'. Use Resume-ToolkitProvisioning -Force ou Reset-ToolkitProvisioningState."
    }

    if (-not $PSCmdlet.ShouldProcess($deploymentId, 'Iniciar provisionamento')) {
        return [pscustomobject]@{ GlobalState = 'Discovered'; RebootAction = 'None'; Report = $null }
    }

    if (-not (Test-Path -LiteralPath $workDir)) {
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $resolvedPath -Destination (Join-Path $workDir 'provisioning.json') -Force

    $moduleVersion = $(if ($module = Get-Module -Name 'WbaToolkit.Provisioning') { $module.Version.ToString() } else { '0.0.0' })

    Invoke-ToolkitProvisioningEngine -DeploymentId $deploymentId -Config $imported.Config -ConfigHash $imported.Sha256 `
        -SchemaVersion ([int]$imported.Config.schemaVersion) -ModuleVersion $moduleVersion `
        -Paths $paths -ExistingState $existing.State
}
