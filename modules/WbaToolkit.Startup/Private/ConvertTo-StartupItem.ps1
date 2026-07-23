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
        [string]$BackupPath,
        # Tipo nativo do valor de registro (String, ExpandString, Binary, DWord, etc.).
        # Necessario para restaurar o valor sem corromper ao reabilitar.
        [string]$ValueKind = 'String',
        # Valor bruto preservando o tipo nativo (ex.: byte[] para REG_BINARY).
        # Command e a forma textual para exibicao; RawValue e usado na restauracao.
        [object]$RawValue
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
        ValueKind       = $ValueKind
        RawValue        = $RawValue
        Enabled         = $Enabled
        State           = if ($Enabled) { 'On' } else { 'Off' }
        ManagedDisabled = $ManagedDisabled
        BackupPath      = $BackupPath
        CanDisable      = $Enabled
        CanEnable       = -not $Enabled
        CanRemove       = $true
    }
}
