function ConvertTo-LicensePartialKey {
    <#
    .SYNOPSIS
        Mascara uma Product Key, mantendo apenas os 5 ultimos caracteres (ADR 0028).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProductKey
    )

    $clean = ($ProductKey -replace '[^A-Za-z0-9]', '')
    if ($clean.Length -le 5) { return '*****' }
    return ('*****-*****-*****-*****-{0}' -f $clean.Substring($clean.Length - 5).ToUpperInvariant())
}
