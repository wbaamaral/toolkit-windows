function New-StartupItemId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').Substring(0, 12).ToLower()
}
