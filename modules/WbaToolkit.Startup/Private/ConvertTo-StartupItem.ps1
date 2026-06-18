function ConvertTo-StartupItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Location,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$ValueName,
        [string]$Command,
        [bool]$Enabled = $true,
        [bool]$ManagedDisabled = $false,
        [string]$BackupPath
    )

    $id = New-StartupItemId -Value "$SourceType|$Location|$Name|$ValueName"
    [pscustomobject]@{
        Id              = $id
        Name            = $Name
        SourceType      = $SourceType
        Scope           = $Scope
        Location        = $Location
        ValueName       = $ValueName
        Command         = $Command
        Enabled         = $Enabled
        State           = if ($Enabled) { 'On' } else { 'Off' }
        ManagedDisabled = $ManagedDisabled
        BackupPath      = $BackupPath
        CanDisable      = $Enabled
        CanEnable       = -not $Enabled
        CanRemove       = $true
    }
}
