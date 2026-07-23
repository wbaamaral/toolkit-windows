function Remove-StartupStoreItem {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Id)

    $path = Join-Path (Get-StartupStorePath) $Id
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
