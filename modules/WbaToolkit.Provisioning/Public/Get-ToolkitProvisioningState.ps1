function Get-ToolkitProvisioningState {
    <#
    .SYNOPSIS
        Le o estado corrente de um deployment.

    .DESCRIPTION
        Wrapper publico de Read-ToolkitProvisioningState. Devolve $null em State quando
        o deployment nunca foi iniciado; sinaliza CorruptionDetected quando state.json e
        state.previous.json falharam ambos.

    .PARAMETER DeploymentId
        Identificador do deployment.

    .EXAMPLE
        Get-ToolkitProvisioningState -DeploymentId 'filial-pvh-estacao-018'

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Found, State, RecoveredFromPrevious, CorruptionDetected.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentId
    )

    $paths = Get-ToolkitProvisioningPaths
    $stateDirectory = Join-Path $paths.Work $DeploymentId

    Read-ToolkitProvisioningState -StateDirectory $stateDirectory
}
