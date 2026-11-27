function ConvertFrom-BackupCreatedAt {
    # Converte o CreatedAt de um metadados.json em [datetime].
    # No Windows PowerShell 5.1, ConvertTo-Json de Get-Date grava um objeto
    # {value, DisplayHint, DateTime}; versoes recentes gravam string ISO 8601.
    # Devolve $null quando nao for possivel determinar a data.
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    if ($Value.PSObject.Properties['value']) { $Value = $Value.value }
    if ($Value -is [datetime]) { return $Value }
    try {
        return [datetime]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        Write-Verbose "CreatedAt ilegivel: '$Value'. $($_.Exception.Message)"
        return $null
    }
}
