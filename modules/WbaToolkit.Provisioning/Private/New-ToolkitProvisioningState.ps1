function New-ToolkitProvisioningState {
    <#
    .SYNOPSIS
        Constroi o objeto de estado inicial para um deployment recem-descoberto.

    .DESCRIPTION
        Campos exigidos por SPEC-PROVISIONING-ENGINE: deploymentId, hash da configuracao,
        versao do schema, versao do modulo, estado global, etapa corrente, resultados
        anteriores, contador de boot, tentativas e timestamps UTC.

    .PARAMETER DeploymentId
    .PARAMETER ConfigHash
    .PARAMETER SchemaVersion
    .PARAMETER ModuleVersion

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentId,

        [Parameter(Mandatory)]
        [string]$ConfigHash,

        [Parameter(Mandatory)]
        [int]$SchemaVersion,

        [Parameter(Mandatory)]
        [string]$ModuleVersion
    )

    $now = (Get-Date).ToUniversalTime().ToString('o')

    [pscustomobject]@{
        DeploymentId  = $DeploymentId
        ConfigHash    = $ConfigHash
        SchemaVersion = $SchemaVersion
        ModuleVersion = $ModuleVersion
        GlobalState   = 'Discovered'
        CurrentStepId = $null
        BootCount     = 0
        StepResults   = @()
        CreatedAt     = $now
        UpdatedAt     = $now
    }
}
