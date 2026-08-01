function Remove-StartupStoreItem {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory = $true)][string]$Id)

    $path = Join-Path (Get-StartupStorePath) $Id
    if (Test-Path -LiteralPath $path) {
        if (-not $PSCmdlet.ShouldProcess($path, 'Remover item de inicializacao armazenado')) {
            return
        }
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
