#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnóstico completo de conectividade com a internet.

.DESCRIPTION
    Invólucro operacional do módulo WbaToolkit.Networking. Mantém o comportamento legado do script
    enquanto a lógica de teste e relatório passa a ser tratada pelo módulo compartilhado.

.PARAMETER Detalhado
    Exibe informações adicionais no relatório em tela.

.EXAMPLE
    .\Testar-Conectividade-Internet.ps1

.EXAMPLE
    .\Testar-Conectividade-Internet.ps1 -Detalhado
#>

[CmdletBinding()]
param(
    [switch]$Detalhado
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

chcp 65001 | Out-Null

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Diagnostics; Related=Diagnostico-Reparo-HD100.ps1; Manual=Teste de conectividade com a internet

$report = Invoke-ConnectivityTest -Detailed:$Detalhado
Show-ConnectivityReport -Report $report
