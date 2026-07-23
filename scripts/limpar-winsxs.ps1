# =============================================================================
# [NAO VALIDADO] Script sem execucao real documentada em Windows.
# Nao recomendado para uso em producao ate validacao operacional.
# Registro: nao-validado/README.md
# =============================================================================
#requires -version 5.1
<#
.SYNOPSIS
    Diagnostico e limpeza assistida do Component Store (WinSxS) do Windows.

.DESCRIPTION
    Analisa e opcionalmente limpa o Component Store via DISM. Disponivel em tres modos:

    Diagnostico (padrao): exibe tamanho e recomendacao de limpeza sem alterar o sistema.
    Limpeza             : executa limpeza via DISM apos confirmacao do operador.
    Relatorio           : como Diagnostico, mas salva resultado em JSON e opcionalmente HTML.

    O nivel padrao de limpeza (Standard) executa /StartComponentCleanup e e reversivel.
    O nivel Aggressive (/ResetBase) e IRREVERSIVEL: remove backups de updates instalados
    e impossibilita rollback de Service Packs. Requer confirmacao explicita.

.PARAMETER Modo
    Diagnostico : analisa o store e exibe resultado; sem alteracoes (padrao).
    Limpeza     : solicita confirmacao e executa limpeza DISM.
    Relatorio   : como Diagnostico, salva JSON e opcionalmente HTML.

.PARAMETER ResetBase
    Apenas em -Modo Limpeza. Ativa /ResetBase no DISM.
    IRREVERSIVEL: remove backups de updates, impossibilita rollback de SPs.

.PARAMETER DryRun
    Simula operacoes destrutivas sem executa-las. Valido apenas em -Modo Limpeza.

.PARAMETER GerarHtml
    Apenas em -Modo Relatorio. Salva tambem relatorio em HTML.

.PARAMETER Path
    Diretorio raiz de relatorios. Padrao: configuracao global ou C:\WBA\Relatorios.

.PARAMETER Help
    Exibe a ajuda resumida do script e encerra.

.EXAMPLE
    .\limpar-winsxs.ps1

.EXAMPLE
    .\limpar-winsxs.ps1 -Modo Relatorio -GerarHtml

.EXAMPLE
    .\limpar-winsxs.ps1 -Modo Limpeza -DryRun

.EXAMPLE
    .\limpar-winsxs.ps1 -Modo Limpeza -ResetBase

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\limpar-winsxs.ps1 -Modo Limpeza

.NOTES
    Recomendado executar como Administrador.
    Testado conceitualmente para Windows 10/11 com PowerShell 5.1 ou superior.
#>
param(
    [ValidateSet('Diagnostico', 'Limpeza', 'Relatorio')]
    [string]$Modo = 'Diagnostico',

    [switch]$ResetBase,
    [switch]$DryRun,
    [switch]$GerarHtml,

    [Alias('DiretorioSaida')]
    [string]$Path,

    [switch]$Help
)
    [switch]$Version

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

chcp 65001 | Out-Null

$ToolkitRoot           = Split-Path -Parent $PSScriptRoot
$CoreModulePath        = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$MaintenanceModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1'
Import-Module $CoreModulePath        -Force -ErrorAction Stop
Import-Module $MaintenanceModulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Maintenance; Related=limpar-windows.ps1; Manual=Limpeza assistida do Component Store WinSxS

$ScriptVersion = 'v1.0.0'
$ScriptName    = $MyInvocation.MyCommand.Name
$ScriptPath    = $PSCommandPath
$ScriptDir     = $PSScriptRoot

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Limpeza do Component Store (WinSxS) — $script:ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$script:ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Modo <modo>       Diagnostico (padrao), Limpeza ou Relatorio."
    Write-Host "  -ResetBase         So em -Modo Limpeza. Ativa /ResetBase (IRREVERSIVEL)."
    Write-Host "  -DryRun            So em -Modo Limpeza. Simula sem executar."
    Write-Host "  -GerarHtml         So em -Modo Relatorio. Salva tambem relatorio HTML."
    Write-Host "  -DiretorioSaida '<dir>' Raiz de relatorios. Padrao: config global ou C:\WBA\Relatorios"
    Write-Host "  -Help              Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$script:ScriptName"
    Write-Host "  .\$script:ScriptName -Modo Relatorio -GerarHtml"
    Write-Host "  .\$script:ScriptName -Modo Limpeza -DryRun"
    Write-Host ""
}

if ($Help) { Show-Help; exit 0 }
if ($Version) { Write-Host "Script: $ScriptName — $ScriptVersion" -ForegroundColor Green; exit 0 }

if (-not (Test-IsAdministrator)) {
    $relaunchCommand = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunchCommand) -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'limpeza'
$LogDir   = $ReportSession.LogsPath
$LogFile  = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$([System.IO.Path]::GetFileNameWithoutExtension($ScriptName)).log"

$transcriptActive = $false
try {
    Start-Transcript -Path $LogFile -ErrorAction Stop
    $transcriptActive = $true
}
catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Title "Limpeza do Component Store (WinSxS) — $ScriptVersion"
Write-Info "Modo : $Modo"
Write-Info "Log  : $LogFile"

Write-Section "Analisando Component Store"
Write-Info "Executando DISM AnalyzeComponentStore..."
$info = Get-ComponentStoreInfo

if ($null -eq $info) {
    Write-Fail "Nao foi possivel obter informacoes do Component Store."
    Write-Warn "Verifique se o sistema esta integro e tente novamente como Administrador."
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

if ($null -ne $info.StoreSizeGB) {
    Write-Info "Tamanho do store   : $($info.StoreSizeGB) GB"
}
if ($null -ne $info.ReclaimableSizeGB) {
    Write-Info "Espaco recuperavel : $($info.ReclaimableSizeGB) GB (backups e recursos desabilitados)"
}
if ($null -ne $info.RecommendedCleanup) {
    $recText = if ($info.RecommendedCleanup) { 'Sim' } else { 'Nao' }
    Write-Info "Limpeza recomendada: $recText"
}
Write-Info "Ultima limpeza     : $($info.LastAnalysisDate)"

switch ($Modo) {

    'Diagnostico' {
        Write-Ok "Diagnostico concluido. Nenhuma alteracao realizada."
    }

    'Limpeza' {
        Write-Section "Limpeza do Component Store"

        if ($null -ne $info.RecommendedCleanup -and -not $info.RecommendedCleanup) {
            Write-Warn "DISM nao recomenda limpeza no momento. O espaco recuperavel pode ser minimo."
        }

        if ($ResetBase) {
            Write-Host ""
            Write-Host "ATENCAO: /ResetBase remove backups de updates instalados." -ForegroundColor Red
            Write-Host "         Rollback de Service Packs sera IMPOSSIVEL apos esta operacao." -ForegroundColor Red
            Write-Host "         Esta operacao e IRREVERSIVEL." -ForegroundColor Red
            Write-Host ""
        }

        $level      = if ($ResetBase) { 'Aggressive' } else { 'Standard' }
        $confirmMsg = if ($ResetBase) {
            'Confirma execucao da limpeza AGRESSIVA (ResetBase) do WinSxS? Esta acao e IRREVERSIVEL.'
        } else {
            'Confirma execucao da limpeza padrao do WinSxS?'
        }

        $confirmado = Read-YesNo -Question $confirmMsg -DefaultYes $false
        if (-not $confirmado) {
            Write-Info "Limpeza cancelada pelo operador."
            if ($transcriptActive) { Stop-Transcript }
            exit 0
        }

        Write-Info "Executando Invoke-ComponentStoreCleanup -Level $level..."
        $resultado = Invoke-ComponentStoreCleanup -Level $level -DryRun:$DryRun

        if ($resultado.Success) {
            if ($DryRun) {
                Write-Ok "DRY-RUN: simulacao concluida. Nenhuma alteracao realizada."
            } else {
                Write-Ok "Limpeza concluida. Espaco liberado: $($resultado.SpaceFreedMB) MB."
            }
        } else {
            Write-Fail "Limpeza falhou (exit code: $($resultado.ExitCode))."
            Write-Verbose $resultado.RawOutput
        }
    }

    'Relatorio' {
        Write-Section "Gerando relatorio"

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $baseName = "winsxs-$($env:COMPUTERNAME)-$ts"
        $jsonPath = Join-Path $ReportSession.Path "$baseName.json"

        # Coletar dados extras do sistema
        $osInfo    = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $winVer    = if ($osInfo) { "$($osInfo.Caption) Build $($osInfo.BuildNumber)" } else { '—' }
        $diskFree  = try { [math]::Round((Get-PSDrive C -ErrorAction SilentlyContinue).Free / 1GB, 2) } catch { 0 }
        $diskTotal = try { [math]::Round(((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue).Size) / 1GB, 2) } catch { 0 }
        $diskUsed  = $diskTotal - $diskFree
        $diskPct   = if ($diskTotal -gt 0) { [int]($diskUsed / $diskTotal * 100) } else { 0 }

        # Calcular dias desde a ultima limpeza
            $daysSinceCleanup = '—'
            if ($info.LastAnalysisDate -and $info.LastAnalysisDate -ne 'N/A') {
                try {
                    $lastDate = [datetime]::Parse($info.LastAnalysisDate)
                    $daysSinceCleanup = ((Get-Date) - $lastDate).Days
                } catch { }
            }

            # Gerar recomendacoes
            $recommendations = @()
            if ($info.RecommendedCleanup) {
                $recommendations += "O DISM recomenda limpeza. Execute: limpar-winsxs.ps1 -Modo Limpeza"
            }
            if ($diskFree -lt 10) {
                $recommendations += "ESPACO CRITICO: disco C: com apenas $diskFree GB livres"
            }
            if ($info.StoreSizeGB -gt 10) {
                $recommendations += "Component Store grande ($($info.StoreSizeGB) GB) — verifique se ha atualizacoes pendentes"
            }
            if ($recommendations.Count -eq 0) {
                $recommendations += "Nenhuma acao necessaria. Sistema dentro dos parametros normais."
            }

        $infoExport = [pscustomobject]@{
            Computador         = $env:COMPUTERNAME
            VersaoWindows      = $winVer
            Data               = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
            VersaoScript       = $ScriptVersion
            StoreSizeGB        = $info.StoreSizeGB
            ReclaimableSizeGB  = $info.ReclaimableSizeGB
            RecommendedCleanup = $info.RecommendedCleanup
            LastAnalysisDate   = $info.LastAnalysisDate
            DiscoLivreGB       = $diskFree
            DiscoTotalGB       = $diskTotal
            ExitCode           = $info.ExitCode
        }

        Write-TextFileUtf8 -Path $jsonPath -Content ($infoExport | ConvertTo-Json -Depth 3)
        Write-Ok "Relatorio JSON: $jsonPath"

        if ($GerarHtml) {
            $htmlPath = Join-Path $ReportSession.Path "$baseName.html"

            # Preparar dados para cards
            $storeSize    = if ($info.StoreSizeGB) { "$([math]::Round($info.StoreSizeGB, 2)) GB" } else { '—' }
            $reclaimSize  = if ($info.ReclaimableSizeGB) { "$([math]::Round($info.ReclaimableSizeGB, 2)) GB" } else { '—' }
            $reclaimPct   = if ($info.StoreSizeGB -gt 0 -and $info.ReclaimableSizeGB) { [int]($info.ReclaimableSizeGB / $info.StoreSizeGB * 100) } else { 0 }
            $cleanRec     = if ($info.RecommendedCleanup) { 'Sim' } else { 'Nao' }
            $cleanBadge   = if ($info.RecommendedCleanup) { 'badge-yellow' } else { 'badge-green' }
            $lastAnalysis = if ($info.LastAnalysisDate) { $info.LastAnalysisDate } else { '—' }

            # Alerta de limpeza recomendada
            $alertHtml = ''
            if ($info.RecommendedCleanup) {
                $alertHtml = @"
  <div class="section" style="border-left:4px solid var(--warning)">
    <div class="section-body" style="background:#fffbeb">
      <strong>&#9888; Atencao:</strong> O DISM recomenda limpeza do Component Store. 
      Execute <code>.\limpar-winsxs.ps1 -Modo Limpeza</code> para recuperar $reclaimSize de espaco.
    </div>
  </div>
"@
            }

            # Tabela de detalhes
            $detailRows = @(
                "<tr><td>Computador</td><td><strong>$($env:COMPUTERNAME)</strong></td></tr>"
                "<tr><td>Versao do Windows</td><td>$winVer</td></tr>"
                "<tr><td>Data da Analise</td><td>$($infoExport.Data)</td></tr>"
                "<tr><td>Versao do Script</td><td>$($infoExport.VersaoScript)</td></tr>"
                "<tr><td>Ultima Analise</td><td>$lastAnalysis</td></tr>"
                "<tr><td>Dias desde Ultima Limpeza</td><td>$daysSinceCleanup</td></tr>"
                "<tr><td>Exit Code</td><td>$($info.ExitCode)</td></tr>"
            )

            # Lista de recomendacoes
            $recHtml = @($recommendations | ForEach-Object { "<li>$_</li>" }) -join "`n            "

            $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WinSxS — $($env:COMPUTERNAME)</title>
<style>
@font-face{font-family:'Inter';font-style:normal;font-weight:400;font-display:swap;src:local('Inter Regular'),local('Segoe UI'),local('sans-serif')}
@font-face{font-family:'Inter';font-style:normal;font-weight:700;font-display:swap;src:local('Inter Bold'),local('Segoe UI Bold'),local('sans-serif')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:400;font-display:swap;src:local('JetBrains Mono Regular'),local('Consolas'),local('monospace')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:700;font-display:swap;src:local('JetBrains Mono Bold'),local('Consolas Bold'),local('monospace')}
:root{--primary:#1e3a5f;--primary-lt:#2d5986;--accent:#2563eb;--success:#16a34a;--warning:#d97706;--danger:#dc2626;--bg:#f0f4f8;--surface:#fff;--border:#e2e8f0;--text:#1e293b;--muted:#64748b;--radius:8px;--font-sans:'Inter','Segoe UI',system-ui,-apple-system,sans-serif;--font-mono:'JetBrains Mono','Consolas',ui-monospace,monospace}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{font-family:var(--font-sans);background:var(--bg);color:var(--text);font-size:14px;line-height:1.5}
header{background:linear-gradient(135deg,var(--primary) 0%,var(--primary-lt) 100%);color:#fff;padding:2rem 2.5rem;display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:1rem}
header .title-block h1{font-size:1.6rem;font-weight:700;letter-spacing:-0.02em}
header .title-block p{opacity:.75;font-size:.85rem;margin-top:.25rem}
header .meta-block{text-align:right;font-size:.8rem;opacity:.8;line-height:1.8}
main{max-width:1100px;margin:1.5rem auto;padding:0 1.5rem}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:1rem;margin-bottom:1.5rem}
.card{background:var(--surface);border-radius:var(--radius);padding:1.1rem 1.25rem;box-shadow:0 1px 6px rgba(0,0,0,.07);border-left:4px solid var(--accent);transition:box-shadow .15s}
.card:hover{box-shadow:0 4px 14px rgba(0,0,0,.12)}
.card-icon{font-size:1.4rem;margin-bottom:.4rem}
.card-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:600}
.card-value{font-size:1.05rem;font-weight:700;color:var(--primary);margin-top:.2rem}
.card-sub{font-size:.75rem;color:var(--muted);margin-top:.15rem}
.section{background:var(--surface);border-radius:var(--radius);box-shadow:0 1px 6px rgba(0,0,0,.07);margin-bottom:1.25rem;overflow:hidden}
.section-hdr{background:var(--primary);color:#fff;padding:.75rem 1.5rem;font-size:.9rem;font-weight:700;display:flex;align-items:center;gap:.5rem}
.section-body{padding:1.25rem 1.5rem}
.data-table{width:100%;border-collapse:collapse;font-size:.82rem}
.data-table thead th{background:#f8fafc;color:var(--primary);font-weight:700;padding:.55rem 1rem;text-align:left;border-bottom:2px solid var(--border);white-space:nowrap}
.data-table tbody td{padding:.5rem 1rem;border-bottom:1px solid #f1f5f9}
.data-table tbody tr:last-child td{border-bottom:none}
.data-table tbody tr:hover td{background:#f8faff}
.kv-table{width:100%;border-collapse:collapse}
.kv-table th{width:220px;font-weight:600;font-size:.8rem;color:var(--muted);text-align:left;padding:.4rem .75rem .4rem 0;border-bottom:1px solid var(--border);vertical-align:top}
.kv-table td{font-size:.85rem;padding:.4rem 0;border-bottom:1px solid var(--border)}
.kv-table tr:last-child th,.kv-table tr:last-child td{border-bottom:none}
.badge{display:inline-block;padding:.15em .55em;border-radius:4px;font-size:.72rem;font-weight:700;white-space:nowrap}
.badge-green{background:#dcfce7;color:#15803d}
.badge-yellow{background:#fef9c3;color:#92400e}
.badge-red{background:#fee2e2;color:#991b1b}
.muted{color:var(--muted)}
.disk-bar{background:#e2e8f0;border-radius:4px;height:10px;overflow:hidden;margin:8px 0}
.disk-fill{height:100%;border-radius:4px;transition:width .3s}
.bar-ok{background:var(--success)}
.bar-warn{background:var(--warning)}
.bar-danger{background:var(--danger)}
footer{text-align:center;color:var(--muted);font-size:.78rem;padding:1.5rem;margin-top:.5rem}
@page{size:A4;margin:15mm}
@media print{body{background:#fff;font-size:11px}header,.section-hdr{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style>
</head>
<body>
<header>
  <div class="title-block">
    <h1>&#128465; Analise do Component Store</h1>
    <p>$($env:COMPUTERNAME) — $($infoExport.Data)</p>
  </div>
  <div class="meta-block">
    <div><strong>$($env:COMPUTERNAME)</strong></div>
    <div>Gerado em: $($infoExport.Data)</div>
    <div>Versao: $($infoExport.VersaoScript)</div>
    <div>Modo: Somente Leitura</div>
  </div>
</header>
<main>
  <div class="cards">
    <div class="card">
      <div class="card-icon">&#128190;</div>
      <div class="card-label">Tamanho Total</div>
      <div class="card-value">$storeSize</div>
      <div class="card-sub">Component Store (WinSxS)</div>
    </div>
    <div class="card" style="border-left-color: var(--success)">
      <div class="card-icon">&#9989;</div>
      <div class="card-label">Espaco Recuperavel</div>
      <div class="card-value" style="color: var(--success)">$reclaimSize</div>
      <div class="card-sub">$reclaimPct% do total</div>
    </div>
    <div class="card" style="border-left-color: var(--warning)">
      <div class="card-icon">&#128260;</div>
      <div class="card-label">Limpeza Recomendada</div>
      <div class="card-value"><span class="badge $cleanBadge">$cleanRec</span></div>
      <div class="card-sub">Recomendacao do DISM</div>
    </div>
    <div class="card">
      <div class="card-icon">&#128187;</div>
      <div class="card-label">Windows</div>
      <div class="card-value" style="font-size:.85rem">$winVer</div>
      <div class="card-sub">Sistema operacional</div>
    </div>
    <div class="card" style="border-left-color: $(if ($diskPct -gt 85) { 'var(--danger)' } elseif ($diskPct -gt 70) { 'var(--warning)' } else { 'var(--success)' })">
      <div class="card-icon">&#128190;</div>
      <div class="card-label">Disco C: Livre</div>
      <div class="card-value" style="color: $(if ($diskPct -gt 85) { 'var(--danger)' } elseif ($diskPct -gt 70) { 'var(--warning)' } else { 'var(--success)' })">$diskFree GB</div>
      <div class="card-sub">de $diskTotal GB ($diskPct% usado)</div>
    </div>
  </div>
  $alertHtml
  <div class="section">
    <div class="section-hdr">&#128203; Detalhes da Analise</div>
    <div class="section-body">
      <table class="kv-table">
        $(($detailRows -join "`n"))
      </table>
    </div>
  </div>
  <div class="section">
    <div class="section-hdr">&#128200; Barra de Ocupacao</div>
    <div class="section-body">
      <div style="display:flex;justify-content:space-between;margin-bottom:.25rem">
        <span class="muted">$storeSize total</span>
        <span><strong>$reclaimSize</strong> recuperavel</span>
      </div>
      <div class="disk-bar"><div class="disk-fill bar-warn" style="width:$reclaimPct%"></div></div>
      <p class="muted" style="margin-top:.4rem;font-size:.78rem">$reclaimPct% do Component Store pode ser recuperado via limpeza.</p>
    </div>
  </div>
  <div class="section">
    <div class="section-hdr">&#128161; Recomendacoes</div>
    <div class="section-body">
      <ul style="margin:0;padding-left:1.2rem;line-height:1.8">
            $recHtml
      </ul>
    </div>
  </div>
</main>
<footer>
  Gerado por $($ScriptName) $($ScriptVersion) em $($infoExport.Data) — somente leitura, nenhuma alteracao realizada.
</footer>
</body>
</html>
"@
            Write-TextFileUtf8 -Path $htmlPath -Content $html
            Write-Ok "Relatorio HTML : $htmlPath"
        }

        Write-Ok "Relatorio concluido. Nenhuma alteracao realizada."
    }
}

if ($transcriptActive) { Stop-Transcript }
