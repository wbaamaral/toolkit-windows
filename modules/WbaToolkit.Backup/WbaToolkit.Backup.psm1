#Requires -Version 5.1
<#
    WbaToolkit.Backup - Modulo de gerenciamento de backup e restore points
    Carrega funcoes publicas e privadas do diretorio estruturado.
#>

$script:ModuleRoot = $PSScriptRoot

$privatePath = Join-Path $script:ModuleRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse | ForEach-Object {
        . $_.FullName
    }
}

$publicPath = Join-Path $script:ModuleRoot 'Public'
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse | ForEach-Object {
        . $_.FullName
    }
}
