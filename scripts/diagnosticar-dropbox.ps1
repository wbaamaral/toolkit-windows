#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostica a saude do cliente Dropbox e gera JSON para normalizacao iterativa.

.DESCRIPTION
    Consolida checagens de saude do cliente Dropbox: processo em execucao, instalacao
    valida, espaco livre em disco, arquivos com nome/caminho problematico, frescor de
    pastas criticas, conectividade com os servidores do Dropbox, proxy do sistema,
    exclusao no Windows Defender e sincronizacao de hora. Reaproveita a classificacao
    de arquivos de Get-DropboxFileReport para apontar itens que podem travar a
    sincronizacao.

    Este script e a FASE 1 do ciclo de normalizacao do Dropbox:

      diagnosticar-dropbox.ps1 -ExportarJson        (gera JSON)
                ↓
      normalizar-dropbox.ps1                         (TUI interativa)
                ↓
      correcoes-propostas.json + HTML                (validacao)
                ↓
      normalizar-dropbox.ps1 -Modo Aplicar           (aplica correcoes)
                ↓
      correcoes-aplicadas.json + HTML (de → para)    (resultado)

    No modo Diagnostico, o script e somente leitura. No modo Assistido, quando o
    processo Dropbox estiver parado ou a exclusao no Defender estiver ausente, o
    operador pode confirmar o reparo guiado.

.PARAMETER Path
    Raiz do Dropbox a diagnosticar. Se omitido, tenta autodetectar via
    Get-DropboxInstallation.

.PARAMETER Modo
    Diagnostico (padrao) ou Assistido. Assistido permite reparo guiado do processo
    e da exclusao no Defender.

.PARAMETER CriticalFolders
    Subpastas relativas consideradas criticas para a checagem de frescor. Alias:
    -LocaisCriticos.

.PARAMETER FreshnessDays
    Numero maximo de dias sem atualizacao nas pastas criticas antes de gerar AVISO.
    Padrao 2.

.PARAMETER ReiniciarProcesso
    Habilita o reparo guiado de reinicio do processo Dropbox em modo Assistido.

.PARAMETER ExcluirDoDefender
    Habilita a adicao guiada de exclusao no Windows Defender em modo Assistido.
    Exige privilegio de Administrador -- a elevacao e solicitada automaticamente
    somente quando este parametro e usado.

.PARAMETER GerarHtml
    Gera tambem o relatorio em HTML.

.PARAMETER AbrirRelatorio
    Abre o relatorio HTML ao final (requer -GerarHtml).

.PARAMETER DiretorioSaida
    Raiz de relatorios. Quando omitido, usa a raiz persistente do toolkit.

.PARAMETER ExportarJson
    Gera tambem o relatorio em JSON (diagnostico-dropbox.json) com a lista
    estruturada dos arquivos problematicos (Caminho, Nome, Tipo, Problemas).
    O JSON gerado e a entrada para normalizar-dropbox.ps1 (fase 2 do ciclo).

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\diagnosticar-dropbox.ps1

    Diagnostico basico com saida TXT.

.EXAMPLE
    .\diagnosticar-dropbox.ps1 -ExportarJson

    Diagnostico com saida TXT + JSON (para normalizacao).

.EXAMPLE
    .\diagnosticar-dropbox.ps1 -GerarHtml -AbrirRelatorio

    Diagnostico com saida TXT + HTML, abre o relatorio.

.EXAMPLE
    .\diagnosticar-dropbox.ps1 -Path 'C:\Dropbox\Thermo BR Sul' -ExportarJson

    Diagnostico de pasta Dropbox especifica com saida JSON.

.EXAMPLE
    .\diagnosticar-dropbox.ps1 -DiretorioSaida 'C:\Temp\Relatorios' -ExportarJson

    Diagnostico com diretorio de saida personalizado.

.EXAMPLE
    .\diagnosticar-dropbox.ps1 -Modo Assistido -ReiniciarProcesso -ExcluirDoDefender -CriticalFolders 'Financeiro','Contratos'

    Diagnostico com reparo guiado (reiniciar processo + exclusao no Defender).

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.Maintenance.

    Ciclo de normalizacao:
      1. diagnosticar-dropbox.ps1 -ExportarJson    (gera JSON)
      2. normalizar-dropbox.ps1                    (TUI interativa)
      3. normalizar-dropbox.ps1 -Modo Aplicar      (aplica correcoes)

    Saida:
      TXT  : <ReportsRoot>\diagnosticar-dropbox\<ddMMyyyy_HHmmss>\diagnostico-dropbox.txt
      HTML : <ReportsRoot>\diagnosticar-dropbox\<ddMMyyyy_HHmmss>\diagnostico-dropbox.html
      JSON : <ReportsRoot>\diagnosticar-dropbox\<ddMMyyyy_HHmmss>\diagnostico-dropbox.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Diagnostico', 'Assistido')]
    [string]$Modo = 'Diagnostico',

    [Parameter(Mandatory = $false)]
    [Alias('LocaisCriticos')]
    [string[]]$CriticalFolders = @(),

    [Parameter(Mandatory = $false)]
    [int]$FreshnessDays = 2,

    [switch]$ReiniciarProcesso,

    [switch]$ExcluirDoDefender,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Parameter(Mandatory = $false)]
    [string]$DiretorioSaida,

    [switch]$ExportarJson,

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
$ScriptVersion = 'v1.0.0'

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Diagnostico do Cliente Dropbox - $ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Path '<dir>'            Raiz do Dropbox. Padrao: autodetectar."
    Write-Host "  -Modo '<modo>'           Diagnostico (padrao) ou Assistido (permite reparo guiado)."
    Write-Host "  -CriticalFolders <lista> Subpastas criticas para checagem de frescor. Alias -LocaisCriticos."
    Write-Host "  -FreshnessDays <n>       Dias maximos sem atualizacao nas pastas criticas. Padrao 2."
    Write-Host "  -ReiniciarProcesso       Reparo guiado do processo Dropbox (modo Assistido)."
    Write-Host "  -ExcluirDoDefender       Reparo guiado de exclusao no Defender (modo Assistido; exige admin)."
    Write-Host "  -GerarHtml               Gera tambem o relatorio em HTML."
    Write-Host "  -AbrirRelatorio          Abre o relatorio HTML ao final."
    Write-Host "  -DiretorioSaida '<dir>'  Raiz de relatorios. Padrao: raiz persistente do toolkit."
    Write-Host "  -ExportarJson            Gera tambem o relatorio JSON (entrada para normalizar-dropbox.ps1)."
    Write-Host "  -Help                    Esta ajuda."
    Write-Host ""
    Write-Host "Saida:"
    Write-Host "  TXT  : <ReportsRoot>\diagnosticar-dropbox\<ddMMyyyy_HHmmss>\diagnostico-dropbox.txt"
    Write-Host "  HTML : <ReportsRoot>\diagnosticar-dropbox\<ddMMyyyy_HHmmss>\diagnostico-dropbox.html"
    Write-Host "  JSON : <ReportsRoot>\diagnosticar-dropbox\<ddMMyyyy_HHmmss>\diagnostico-dropbox.json"
    Write-Host ""
    Write-Host "Ciclo de normalizacao:"
    Write-Host "  1. diagnosticar-dropbox.ps1 -ExportarJson    (gera JSON)"
    Write-Host "  2. normalizar-dropbox.ps1                    (TUI interativa)"
    Write-Host "  3. normalizar-dropbox.ps1 -Modo Aplicar      (aplica correcoes)"
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -ExportarJson"
    Write-Host "  .\$ScriptName -GerarHtml -AbrirRelatorio"
    Write-Host "  .\$ScriptName -Path 'C:\Dropbox\Thermo BR Sul' -ExportarJson"
    Write-Host "  .\$ScriptName -DiretorioSaida 'C:\Temp\Relatorios' -ExportarJson"
    Write-Host "  .\$ScriptName -Modo Assistido -ReiniciarProcesso -ExcluirDoDefender"
    Write-Host ""
}

# Despacha -Help antes de qualquer verificacao de modulo ou elevacao (ADR 0021).
if ($Help) { Show-Help; exit 0 }

# === Dependencias: adicionar modules/ ao PSModulePath (padrao-dependencias-modulos.md) ===
$moduleRoot = Join-Path $ToolkitRoot 'modules'
if ($env:PSModulePath -notlike "*$moduleRoot*") {
    $env:PSModulePath = "$moduleRoot;$env:PSModulePath"
}

$coreModuleRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$maintModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Maintenance'

foreach ($mod in @($coreModuleRoot, $maintModuleRoot)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        Write-Host "        Solucao: verifique o clone do repositorio em $ToolkitRoot" -ForegroundColor Yellow
        exit 1
    }
}

try {
    foreach ($modRoot in @($coreModuleRoot, $maintModuleRoot)) {
        foreach ($sub in @('Private', 'Public')) {
            $dir = Join-Path $modRoot $sub
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction Stop | ForEach-Object { . $_.FullName }
            }
        }
    }
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos do toolkit." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "        Solucao: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force" -ForegroundColor Yellow
    exit 1
}

# WBA-DOCS: Category=Diagnostico; Related=auditar-arquivos-dropbox.ps1; Manual=Diagnostico de saude do cliente Dropbox

# Elevacao somente quando -ExcluirDoDefender foi solicitado (o restante do script e read-only ou nao exige admin).
if ($ExcluirDoDefender -and -not (Test-IsAdministrator)) {
    Write-Warn 'Privilegio de Administrador necessario para -ExcluirDoDefender. Solicitando elevacao...'
    $relaunchCommand = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunchCommand) -Verb RunAs
    exit
}

function Resolve-DropboxDiagnosticPath {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $candidate = [Environment]::ExpandEnvironmentVariables($Path)
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            throw "Diretorio nao encontrado: $candidate"
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    Write-Info 'Localizando instalacao do Dropbox...'
    $installations = @(Get-DropboxInstallation)

    if ($installations.Count -eq 1) {
        return $installations[0].Caminho
    }

    if ($installations.Count -gt 1) {
        Write-Host ''
        Write-Host 'Foram encontradas varias pastas do Dropbox:'
        Write-Host ''
        for ($i = 0; $i -lt $installations.Count; $i++) {
            Write-Host ('[{0}] {1,-12} {2}' -f ($i + 1), $installations[$i].Conta, $installations[$i].Caminho)
        }
        Write-Host ''

        while ($true) {
            $selection = Read-UserInput -Question 'Selecione o numero da pasta Dropbox'
            $number = 0
            if ([int]::TryParse($selection, [ref]$number)) {
                $index = $number - 1
                if ($index -ge 0 -and $index -lt $installations.Count) {
                    return $installations[$index].Caminho
                }
            }
            Write-Warn 'Selecao invalida.'
        }
    }

    Write-Warn 'Nao foi possivel localizar automaticamente a pasta do Dropbox.'
    while ($true) {
        $manualPath = Read-UserInput -Question 'Informe manualmente o caminho da pasta Dropbox'
        $manualPath = [Environment]::ExpandEnvironmentVariables($manualPath.Trim('"'))
        if (Test-Path -LiteralPath $manualPath -PathType Container) {
            return (Resolve-Path -LiteralPath $manualPath).Path
        }
        Write-Warn "Diretorio nao encontrado: $manualPath"
    }
}

$reportSession = Initialize-ToolkitReportSession -ReportsRoot $DiretorioSaida -ModuleName 'diagnosticar-dropbox'
$textReportPath = Join-Path $reportSession.Path 'diagnostico-dropbox.txt'
$htmlReportPath = Join-Path $reportSession.Path 'diagnostico-dropbox.html'
$jsonReportPath = Join-Path $reportSession.Path 'diagnostico-dropbox.json'

Write-Title "Diagnostico do Cliente Dropbox - $ScriptVersion"

try {
    $resolvedPath = Resolve-DropboxDiagnosticPath
}
catch {
    Write-Fail "Nao foi possivel resolver a pasta do Dropbox: $($_.Exception.Message)"
    exit 1
}

Write-Info "Pasta analisada: $resolvedPath"
Write-Info "Modo: $Modo"
Write-Info 'Executando checagens... (a checagem de arquivos-problema pode levar varios minutos em pastas corporativas grandes)'
Write-Host ''

try {
    $health = Invoke-DropboxHealthCheck -Path $resolvedPath -CriticalFolders $CriticalFolders -FreshnessDays $FreshnessDays
}
catch {
    Write-Fail "Erro durante o diagnostico: $($_.Exception.Message)"
    exit 1
}

foreach ($check in $health.Checks) {
    $line = "[$($check.Categoria)] $($check.Nome): $($check.Detalhe)"
    switch ($check.Status) {
        'OK'     { Write-Ok $line }
        'AVISO'  { Write-Warn $line }
        'FALHA'  { Write-Fail $line }
        'PULADO' { Write-Info $line }
    }
    if (-not [string]::IsNullOrWhiteSpace($check.Recomendacao)) {
        Write-Info "  Recomendacao: $($check.Recomendacao)"
    }
}

Write-Host ''
Write-Title "Resumo Dropbox - $($health.Label)"
Write-Info "Pontuacao : $($health.Score)/100"
Write-Info "Criticas  : $($health.CriticalCount)"
Write-Info "Avisos    : $($health.WarningCount)"
Write-Host ''

# === Relatorio texto ========================================================
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Diagnostico do cliente Dropbox - $ScriptVersion") | Out-Null
$lines.Add("Pasta analisada : $resolvedPath") | Out-Null
$lines.Add("Modo            : $Modo") | Out-Null
$lines.Add("Status          : $($health.Label)") | Out-Null
$lines.Add("Pontuacao       : $($health.Score)/100") | Out-Null
    $lines.Add("Falhas criticas : $($health.CriticalCount)") | Out-Null
    $lines.Add("Avisos          : $($health.WarningCount)") | Out-Null
    $lines.Add('') | Out-Null
    foreach ($check in $health.Checks) {
        $lines.Add(("[{0}] {1} - {2} :: {3}" -f $check.Categoria, $check.Nome, $check.Status, $check.Detalhe)) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($check.Recomendacao)) {
            $lines.Add("  Recomendacao: $($check.Recomendacao)") | Out-Null
        }
    }
Write-TextFileUtf8 -Path $textReportPath -Content (($lines -join "`r`n") + "`r`n")

# === Exportacao em JSON ====================================================
if ($ExportarJson) {
    # Usa $health.FileReport (dado estruturado de Get-DropboxFileReport) em vez
    # de parsear o Detalhe textual da checagem. Cada item tem ProblemFlags (array).
    $allFiles = @($health.FileReport)
    $problematicFiles = @(
        $allFiles | Where-Object { $_.ProblemFlags -and @($_.ProblemFlags).Count -gt 0 } | ForEach-Object {
            [pscustomobject]@{
                Caminho           = [string]$_.Caminho
                Nome              = [string]$_.Nome
                Tipo              = [string]$_.Tipo
                TamanhoBytes      = $_.TamanhoBytes
                Problemas         = @($_.ProblemFlags)
                UltimaModificacao = $_.UltimaModificacao
            }
        }
    )

    $jsonObj = [pscustomobject]@{
        metadata = [pscustomobject]@{
            data_geracao      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            versao_toolkit    = $ScriptVersion
            caminho_analisado = $resolvedPath
        }
        estatisticas = [pscustomobject]@{
            total_arquivos      = $allFiles.Count
            total_problematicos = $problematicFiles.Count
            percentual          = if ($allFiles.Count -gt 0) { [math]::Round(($problematicFiles.Count / $allFiles.Count) * 100, 2) } else { 0 }
        }
        arquivos_problematicos = $problematicFiles
    }

    Write-TextFileUtf8 -Path $jsonReportPath -Content ($jsonObj | ConvertTo-Json -Depth 6)
}

if ($GerarHtml) {
    $html = New-DropboxDoctorHtmlReport -DropboxPath $resolvedPath -Score $health.Score -Label $health.Label `
        -CriticalCount $health.CriticalCount -WarningCount $health.WarningCount -Checks $health.Checks
    Write-TextFileUtf8 -Path $htmlReportPath -Content $html
}

# === Reparo guiado (Modo Assistido) ========================================
if ($Modo -eq 'Assistido' -and $ReiniciarProcesso) {
    $processFail = @($health.Checks | Where-Object { $_.Nome -eq 'Processo dropbox.exe' -and $_.Status -eq 'FALHA' })
    if ($processFail.Count -gt 0) {
        Write-Host ''
        Write-Warn 'O processo Dropbox nao esta em execucao.'
        if (Read-YesNo -Question 'Deseja reiniciar o processo Dropbox agora?' -DefaultYes $true) {
            $restart = Restart-DropboxProcess
            if ($restart.Success) { Write-Ok $restart.Message } else { Write-Fail $restart.Message }
        }
    }
}

if ($Modo -eq 'Assistido' -and $ExcluirDoDefender) {
    $defenderWarn = @($health.Checks | Where-Object { $_.Nome -eq 'Exclusao no Defender' -and $_.Status -eq 'AVISO' })
    if ($defenderWarn.Count -gt 0) {
        Write-Host ''
        Write-Warn 'O caminho do Dropbox nao esta excluido do Windows Defender.'
        if (Read-YesNo -Question 'Deseja adicionar a exclusao no Defender agora?' -DefaultYes $true) {
            $exclusion = Add-DropboxDefenderExclusion -Path @($resolvedPath)
            if ($exclusion.Success) { Write-Ok $exclusion.Message } else { Write-Fail $exclusion.Message }
        }
    }
}

Write-Host ''
Write-Info "Relatorio texto: $textReportPath"
if ($GerarHtml) {
    Write-Info "Relatorio HTML : $htmlReportPath"
    if ($AbrirRelatorio) {
        try { Start-Process $htmlReportPath | Out-Null }
        catch { Write-Warn "Nao foi possivel abrir o relatorio HTML: $($_.Exception.Message)" }
    }
}
if ($ExportarJson) {
    Write-Info "Relatorio JSON : $jsonReportPath"
}

# === Proximo passo =========================================================
if ($ExportarJson) {
    Write-Host ''
    Write-Title "Proximo passo"
    Write-Info "Para normalizar os arquivos problematicos interativamente:"
    Write-Host "  .\scripts\normalizar-dropbox.ps1 -InputFile '$jsonReportPath'" -ForegroundColor Yellow
    Write-Host ''
}

if ($health.CriticalCount -gt 0) {
    exit 2
}
elseif ($health.WarningCount -gt 0) {
    exit 1
}
else {
    exit 0
}
