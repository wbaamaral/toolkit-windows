# Projeto: wba-toolkit
# Autor: wbaamaral

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
$publicPath  = Join-Path $PSScriptRoot 'Public'

foreach ($file in @(Get-ChildItem -Path $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
    . $file.FullName
}

foreach ($file in @(Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
    . $file.FullName
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
)
