# Projeto: wba-toolkit
# Autor: wbaamaral

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$coreModuleRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'WbaToolkit.Core'
if (-not (Test-Path -LiteralPath $coreModuleRoot -PathType Container)) {
    throw "Modulo WbaToolkit.Core nao encontrado: $coreModuleRoot"
}

foreach ($folder in @('Private', 'Public')) {
    $corePath = Join-Path $coreModuleRoot $folder
    if (-not (Test-Path -LiteralPath $corePath -PathType Container)) {
        throw "Diretorio $folder do WbaToolkit.Core nao encontrado: $corePath"
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $corePath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

foreach ($folder in @('Private', 'Steps', 'Public')) {
    $dir = Join-Path $PSScriptRoot $folder
    if (Test-Path -LiteralPath $dir) {
        foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -Recurse)) {
            . $file.FullName
        }
    }
}

Export-ModuleMember -Function @(
    'Install-ToolkitProvisioning'
    'Uninstall-ToolkitProvisioning'
    'Enable-ToolkitProvisioning'
    'Disable-ToolkitProvisioning'
    'Test-ToolkitProvisioningConfig'
    'Get-ToolkitProvisioningConfig'
    'Get-ToolkitProvisioningState'
    'Reset-ToolkitProvisioningState'
    'Invoke-ToolkitProvisioning'
    'Resume-ToolkitProvisioning'
    'Get-ToolkitProvisioningResult'
)
