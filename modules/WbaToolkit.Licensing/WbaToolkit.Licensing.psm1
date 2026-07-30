Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path -LiteralPath $privatePath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Backup-LicenseState',
    'ConvertTo-LicenseInfoObject',
    'Get-LicenseCycleStatus',
    'Get-LicenseHardwareContext',
    'Get-OemProductKey',
    'Get-SoftwareLicensingProduct',
    'Get-SoftwareLicensingService',
    'Invoke-Slmgr',
    'Restore-LicenseState',
    'Test-LicenseAdminContext',
    'Test-ProductKeyFormat'
)
