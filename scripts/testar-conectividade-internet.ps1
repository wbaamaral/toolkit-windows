# =============================================================================
# [NAO VALIDADO] Script sem execucao real documentada em Windows.
# Nao recomendado para uso em producao ate validacao operacional.
# Registro: nao-validado/README.md
# =============================================================================
#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnóstico completo de conectividade com a internet.

.DESCRIPTION
    Invólucro operacional do módulo WbaToolkit.Networking. Mantém o comportamento legado do script
    enquanto a lógica de teste e relatório passa a ser tratada pelo módulo compartilhado.

.PARAMETER Detalhado
    Exibe informações adicionais no relatório em tela.

.PARAMETER Help
    Exibe a ajuda resumida do script e encerra.

.EXAMPLE
    .\testar-conectividade-internet.ps1

.EXAMPLE
    .\testar-conectividade-internet.ps1 -Detalhado
#>

[CmdletBinding()]
param(
    [switch]$Detalhado,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null } catch { }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Teste de Conectividade com a Internet" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Detalhado         Exibe informacoes adicionais no relatorio em tela."
    Write-Host "  -Help              Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Detalhado"
    Write-Host ""
}

if ($Help) { Show-Help; exit 0 }

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Diagnostics; Related=diagnosticar-disco-100.ps1; Manual=Teste de conectividade com a internet

$report = Invoke-ConnectivityTest -Detailed:$Detalhado
Show-ConnectivityReport -Report $report
