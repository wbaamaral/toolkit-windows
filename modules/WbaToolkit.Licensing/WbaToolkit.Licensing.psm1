Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($folder in @('Private', 'Public')) {
    $path = Join-Path $PSScriptRoot $folder
    if (Test-Path -LiteralPath $path) {
        foreach ($file in @(Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File)) {
            . $file.FullName
        }
    }
}

Export-ModuleMember -Function @(
    'Backup-LicenseState',
    'Get-LicenseCycleStatus',
    'Get-WindowsLicenseInfo',
    'Resolve-LicenseError',
    'Restore-LicenseState'
)