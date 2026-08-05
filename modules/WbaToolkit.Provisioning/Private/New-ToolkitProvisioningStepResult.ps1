function New-ToolkitProvisioningStepResult {
    <#
    .SYNOPSIS
        Constroi o objeto de resultado tipado de uma etapa (SPEC-PROVISIONING-ENGINE).

    .PARAMETER StepId
    .PARAMETER Status
        Skipped | Compliant | Changed | Failed | RebootRequired.
    .PARAMETER Changed
    .PARAMETER RebootRequired
    .PARAMETER Attempt
    .PARAMETER StartedAt
    .PARAMETER CompletedAt
    .PARAMETER Message
    .PARAMETER ErrorCode
    .PARAMETER Evidence
        Dados ja sanitizados (o chamador deve ter passado por Protect-ToolkitProvisioningLogValue).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [ValidateSet('Skipped', 'Compliant', 'Changed', 'Failed', 'RebootRequired')]
        [string]$Status,

        [bool]$Changed = $false,
        [bool]$RebootRequired = $false,

        [Parameter(Mandatory)]
        [int]$Attempt,

        [Parameter(Mandatory)]
        [datetime]$StartedAt,

        [datetime]$CompletedAt = (Get-Date),

        [string]$Message = '',
        [string]$ErrorCode = '',

        $Evidence = $null
    )

    [pscustomobject]@{
        StepId         = $StepId
        Status         = $Status
        Changed        = $Changed
        RebootRequired = $RebootRequired
        Attempt        = $Attempt
        StartedAt      = $StartedAt.ToUniversalTime().ToString('o')
        CompletedAt    = $CompletedAt.ToUniversalTime().ToString('o')
        Message        = $Message
        ErrorCode      = $ErrorCode
        Evidence       = $Evidence
    }
}
