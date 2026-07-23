function Test-ProductKeyFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$ProductKey
    )
    return ($ProductKey -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$')
}
