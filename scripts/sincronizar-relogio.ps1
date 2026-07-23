#Requires -Version 5.1
<#!
.SYNOPSIS
    Verifica e corrige a sincronização de relógio e o fuso horário do Windows.

.DESCRIPTION
    Em clientes Active Directory usa a hierarquia de tempo do domínio. Fora do
    domínio usa pool.ntp.br por padrão ou time.windows.com. A execução padrão
    é somente diagnóstico; -Corrigir aplica alterações com elevação.

.PARAMETER Corrigir
    Aplica a configuração de tempo e, se informado, o fuso horário.

.PARAMETER NtpServer
    Fonte NTP externa fora do domínio. Padrão: pool.ntp.br.

.PARAMETER TimeZoneId
    ID do fuso horário Windows. Sem este parâmetro o fuso apenas é verificado.

.PARAMETER GerarHtml
    Gera também o relatório HTML.

.PARAMETER DiretorioSaida
    Raiz dos relatórios. Padrão: configuração persistente ou C:\WBA\Relatorios.

.PARAMETER Help
    Exibe esta ajuda e encerra.
#>
[CmdletBinding()]
param(
    [switch]$Corrigir,

    [ValidateSet('pool.ntp.br', 'time.windows.com')]
    [string]$NtpServer = 'pool.ntp.br',

    [string]$TimeZoneId,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Alias('Path')]
    [string]$DiretorioSaida,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

function Show-Help {
    Write-Host ''
    Write-Host 'Sincronização de relógio do Windows' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Uso: .\$($MyInvocation.ScriptName | Split-Path -Leaf) [opções]"
    Write-Host ''
    Write-Host '  -Corrigir                 Aplica a fonte de tempo e alterações autorizadas.'
    Write-Host '  -NtpServer <servidor>     pool.ntp.br (padrão) ou time.windows.com.'
    Write-Host '  -TimeZoneId <id>          Fuso a aplicar somente com -Corrigir.'
    Write-Host '  -GerarHtml                Gera relatório HTML.'
    Write-Host '  -DiretorioSaida <pasta>   Raiz dos relatórios.'
    Write-Host '  -AbrirRelatorio           Abre o HTML ao final.'
    Write-Host '  -Help                     Esta ajuda.'
    Write-Host ''
    Write-Host 'Exemplos:'
    Write-Host '  .\sincronizar-relogio.ps1'
    Write-Host '  .\sincronizar-relogio.ps1 -Corrigir'
    Write-Host '  .\sincronizar-relogio.ps1 -Corrigir -TimeZoneId ''E. South America Standard Time'''
    Write-Host ''
}

if ($Help) { Show-Help; exit 0 }

$toolkitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $toolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Force -ErrorAction Stop
Import-Module (Join-Path $toolkitRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1') -Force -ErrorAction Stop

if ($Corrigir -and -not (Test-IsAdministrator)) {
    Write-Warning 'A correção exige privilégios administrativos. Solicitando elevação...'
    $command = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) -Verb RunAs
    exit 0
}

$session = Initialize-ToolkitReportSession -ReportsRoot $DiretorioSaida -ModuleName 'sincronizar-relogio'
$result = Sync-ComputerTime -Apply:$Corrigir -NtpServer $NtpServer -TimeZoneId $TimeZoneId

$jsonPath = Join-Path $session.Path 'sincronizar-relogio.json'
$textPath = Join-Path $session.Path 'sincronizar-relogio.txt'
$htmlPath = Join-Path $session.Path 'sincronizar-relogio.html'
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('WBA Windows Toolkit — Sincronização de relógio')
$lines.Add(('Gerado em       : {0}' -f $result.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')))
$lines.Add(('Computador      : {0}' -f $result.ComputerName))
$lines.Add(('Ingressado no AD: {0}' -f $result.PartOfDomain))
$lines.Add(('Domínio         : {0}' -f $result.Domain))
$lines.Add(('Modo de fonte   : {0}' -f $result.SourceMode))
$lines.Add(('Fonte anterior   : {0}' -f $result.SourceBefore))
$lines.Add(('Fonte posterior  : {0}' -f $result.SourceAfter))
$lines.Add(('Fuso anterior    : {0}' -f $result.TimeZoneBefore))
$lines.Add(('Fuso posterior   : {0}' -f $result.TimeZoneAfter))
$lines.Add(('Serviço W32Time  : {0}' -f $result.ServiceStatus))
$lines.Add(('Correção pedida  : {0}' -f $result.ApplyRequested))
$lines.Add('')
$lines.Add('Ações:')
foreach ($action in @($result.Actions)) { $lines.Add("- $action") }
$lines.Add('')
$lines.Add('Erros:')
if (@($result.Errors).Count -eq 0) { $lines.Add('- nenhum') }
else { foreach ($errorMessage in @($result.Errors)) { $lines.Add("- $errorMessage") } }
$lines | Set-Content -LiteralPath $textPath -Encoding UTF8

if ($GerarHtml -or $AbrirRelatorio) {
    $safe = {
        param([object]$Value)
        ([string]$Value).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    }
    $statusClass = if ($result.Success) { 'badge-green' } else { 'badge-red' }
    $body = @"
<div class="cards">
  <div class="card"><div class="card-label">Estado</div><div class="card-value"><span class="badge $statusClass">$([string]$result.Success)</span></div></div>
  <div class="card"><div class="card-label">Fonte</div><div class="card-value">$(& $safe $result.SourceAfter)</div></div>
  <div class="card"><div class="card-label">Fuso</div><div class="card-value">$(& $safe $result.TimeZoneAfter)</div></div>
  <div class="card"><div class="card-label">Domínio</div><div class="card-value">$(& $safe $(if ($result.PartOfDomain) { $result.Domain } else { 'fora do domínio' }))</div></div>
</div>
<section class="section"><div class="section-hdr">Estado do relógio</div><div class="section-body"><table class="kv-table">
<tr><th>Fonte anterior</th><td>$(& $safe $result.SourceBefore)</td></tr>
<tr><th>Fonte posterior</th><td>$(& $safe $result.SourceAfter)</td></tr>
<tr><th>Modo</th><td>$(& $safe $result.SourceMode)</td></tr>
<tr><th>Serviço W32Time</th><td>$(& $safe $result.ServiceStatus)</td></tr>
<tr><th>Fuso anterior</th><td>$(& $safe $result.TimeZoneBefore)</td></tr>
<tr><th>Fuso posterior</th><td>$(& $safe $result.TimeZoneAfter)</td></tr>
</table></div></section>
<section class="section"><div class="section-hdr">Ações e erros</div><div class="section-body"><ul>
$(($result.Actions + $result.Errors | ForEach-Object { '<li>' + (& $safe $_) + '</li>' }) -join "`n")
</ul></div></section>
"@
    $html = New-ToolkitHtmlReport -Title 'Sincronização de relógio' -Subtitle $result.ComputerName -Icon '&#128336;' -Body $body
    $html | Set-Content -LiteralPath $htmlPath -Encoding UTF8
}

Write-Host "Relatório TXT : $textPath" -ForegroundColor Cyan
Write-Host "Relatório JSON: $jsonPath" -ForegroundColor Cyan
if (Test-Path -LiteralPath $htmlPath) { Write-Host "Relatório HTML : $htmlPath" -ForegroundColor Cyan }
if ($AbrirRelatorio -and (Test-Path -LiteralPath $htmlPath)) { Start-Process $htmlPath }
if (-not $result.Success) { exit 1 }
