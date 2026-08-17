# Projeto: wba-toolkit
# Autor: wbaamaral

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path -LiteralPath $privatePath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path -LiteralPath $publicPath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Get-DefaultUserHivePath'
    'Invoke-WithDefaultUserHive'
    'Import-RegistryTweakToDefaultProfile'
    'Test-SysprepEnvironment'
    'Invoke-SysprepPreparation'
    'Remove-SafePath'
    'Get-DiskInfo'
    'Get-FilesystemErrorEvent'
    'Write-MaintenanceEvent'
    'Invoke-FilesystemCheck'
    'Invoke-EventLogMaintenance'
    'Get-ComponentStoreInfo'
    'Invoke-ComponentStoreCleanup'
    'Sync-ComputerTime'
    'Get-DropboxInstallation'
    'Get-DropboxFileReport'
    'Invoke-DropboxHealthCheck'
    'Restart-DropboxProcess'
    'Add-DropboxDefenderExclusion'
)
