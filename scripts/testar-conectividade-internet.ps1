#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnóstico completo de conectividade com a internet.

.DESCRIPTION
    Invólucro operacional do módulo WbaToolkit.Networking. Executa testes de
    camada física até aplicação (ICMP, DNS, TCP, HTTP, download) e gera relatórios
    em TXT, JSON e opcionalmente HTML.

.PARAMETER Detalhado
    Exibe informações adicionais no relatório em tela.

.PARAMETER GerarHtml
    Gera relatório HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatório HTML (ou JSON, se HTML não foi gerado) ao final da execução.

.PARAMETER Path
    Diretório raiz de relatórios. Padrão: configuração persistente ou C:\WBA\Relatorios.

.PARAMETER Help
    Exibe a ajuda resumida do script e encerra.

.EXAMPLE
    .\testar-conectividade-internet.ps1

.EXAMPLE
    .\testar-conectividade-internet.ps1 -Detalhado -GerarHtml

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos:
      - WbaToolkit.Core (obrigatório)
      - WbaToolkit.Networking (obrigatório)
#>

[CmdletBinding()]
param(
    [switch]$Detalhado,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Alias('DiretorioSaida')]
    [string]$Path,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null }
catch { Write-Verbose "Nao foi possivel ajustar a pagina de codigo do console para UTF-8: $($_.Exception.Message)" }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Teste de Conectividade com a Internet" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Detalhado         Exibe informacoes adicionais no relatorio em tela."
    Write-Host "  -GerarHtml         Gera relatorio HTML adicional."
    Write-Host "  -AbrirRelatorio    Abre o relatorio ao final da execucao."
    Write-Host "  -Path '<dir>'      Raiz dos relatorios. Padrao: ReportsRoot ou C:\WBA\Relatorios."
    Write-Host "  -Help              Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Detalhado -GerarHtml"
    Write-Host "  .\$ScriptName -Path 'C:\Temp\relatorios'"
    Write-Host ""
}

if ($Help) { Show-Help; exit 0 }

$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$netModuleRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.Networking'

foreach ($mod in @($coreModuleRoot, $netModuleRoot)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot, $netModuleRoot)) {
        foreach ($sub in @('Private', 'Public')) {
            $dir = Join-Path $moduleRoot $sub
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
            }
        }
    }
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos do toolkit." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

# WBA-DOCS: Category=Diagnostics; Related=diagnosticar-disco-100.ps1; Manual=Teste de conectividade com a internet

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'conectividade-internet'
$LogDir = $ReportSession.LogsPath
$LogFile = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$ScriptName.log"

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$transcriptActive = $false
try {
    Start-Transcript -Path $LogFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
}
catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Teste de Conectividade com a Internet" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Log: $LogFile" -ForegroundColor Yellow
Write-Host ""

try {
    $report = Invoke-ConnectivityTest -Detailed:$Detalhado -ErrorAction Stop
}
catch {
    Write-Fail "Erro durante os testes de conectividade: $($_.Exception.Message)"
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

Show-ConnectivityReport -Report $report

$jsonPath = Join-Path $ReportSession.Path 'conectividade-internet.json'
$txtPath  = Join-Path $ReportSession.Path 'conectividade-internet.txt'

$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$generatedAt = if ($null -ne $report.FinishedAt) { $report.FinishedAt } elseif ($null -ne $report.StartedAt) { $report.StartedAt } else { Get-Date }
$computerName = if ($report.Context -and $report.Context.Hostname) { $report.Context.Hostname } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'N/I' }
$overall = if ($report.Blocked) { 'BLOQUEADO: ' + $report.BlockReason }
           elseif ($report.Summary) {
               if ($report.Summary.Failed -gt 0 -or $report.Summary.Error -gt 0) { 'FALHA' }
               elseif ($report.Summary.Warning -gt 0) { 'AVISO' }
               else { 'OK' }
           } else { 'N/I' }

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('WBA Windows Toolkit — Teste de Conectividade com a Internet')
$lines.Add(('Gerado em       : {0}' -f $generatedAt.ToString('yyyy-MM-dd HH:mm:ss')))
$lines.Add(('Computador      : {0}' -f $computerName))
$lines.Add(('Resultado geral : {0}' -f $overall))
if ($report.Summary) {
    $lines.Add(('Resumo          : Total={0} Sucesso={1} Falhas={2} Avisos={3} Inconclusivo={4}' -f $report.Summary.Total, $report.Summary.Success, $report.Summary.Failed, $report.Summary.Warning, $report.Summary.Inconclusive))
}
$lines.Add('')
$lines.Add('Testes:')
foreach ($test in @($report.Results)) {
    $testName = if ($test.TestName) { $test.TestName } elseif ($test.Name) { $test.Name } else { 'Teste' }
    $status = if ($test.Success) { 'OK' } else { 'FALHA' }
    $detail = if ($test.Status) { $test.Status } elseif ($test.Detail) { $test.Detail } else { '' }
    $targetInfo = if ($test.Target) { " [$($test.Target)]" } else { '' }
    $lines.Add(('  [{0}] {1}{2} - {3}' -f $status, $testName, $targetInfo, $detail))
    if ($test.Recommendation) { $lines.Add(('        Dica: {0}' -f $test.Recommendation)) }
    elseif ($test.Detail -and $test.Detail -ne $detail) { $lines.Add(('        {0}' -f $test.Detail)) }
    if ($test.ErrorMessage) { $lines.Add(('        Erro: {0}' -f $test.ErrorMessage)) }
}
$lines | Set-Content -LiteralPath $txtPath -Encoding UTF8

Write-Host ""
Write-Ok "Relatorios salvos em: $($ReportSession.Path)"
Write-Host "  JSON: $jsonPath" -ForegroundColor Cyan
Write-Host "  TXT:  $txtPath" -ForegroundColor Cyan

if ($GerarHtml) {
    try {
        $htmlResult = Export-ConnectivityReport -Report $report -Path $ReportSession.Path
        if ($htmlResult.Success) {
            Write-Host "  HTML: $($htmlResult.Path)" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "Nao foi possivel gerar o relatorio HTML: $($_.Exception.Message)"
    }
}

if ($AbrirRelatorio) {
    $openPath = if ($GerarHtml -and (Test-Path $htmlResult.Path)) {
        $htmlResult.Path
    } else {
        $jsonPath
    }
    if (Test-Path $openPath) {
        Start-Process $openPath
    }
}

if ($transcriptActive) { Stop-Transcript }

Write-Host ""
Write-Ok "Teste de conectividade concluido."
