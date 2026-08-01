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
    'Get-InventoryCoverageMap'
)
