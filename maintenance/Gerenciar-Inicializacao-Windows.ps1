#requires -version 5.1
<#
.SYNOPSIS
    Gerenciamento exclusivo de itens de inicializacao e servicos do Windows.

.DESCRIPTION
    Ferramenta dedicada ao gerenciamento da inicializacao do Windows. Coleta, exibe
    e permite modificar entradas das tres fontes reconhecidas pelo toolkit:

      - Registro (HKLM/HKCU Run e RunOnce)
      - Pasta de inicializacao (usuario e sistema)
      - Tarefas agendadas com gatilho de logon ou boot

    Adicionalmente, exibe o estado e tipo de inicializacao dos servicos relevantes.

    No modo Diagnostico (padrao), apenas coleta e exibe informacoes sem alterar nada.
    No modo Assistido, permite ao operador desabilitar, reativar ou remover entradas.

    Todas as operacoes de desativacao sao reversiveis: o item original e registrado
    no repositorio WBA (HKLM:\SOFTWARE\WBA\WindowsToolkit\Startup\Disabled) antes
    de qualquer alteracao.

.PARAMETER Modo
    Define o modo de execucao:
      Diagnostico - leitura e relatorio apenas (padrao)
      Assistido   - permite modificacoes interativas

.PARAMETER DryRun
    Simula todas as operacoes sem efetuar alteracoes no sistema.

.PARAMETER GerarHtml
    Gera relatorio HTML alem do TXT e JSON.

.PARAMETER DiretorioSaida
    Raiz de relatorios escolhida pelo usuario. Quando omitido, usa a configuracao
    persistente do toolkit ou C:\WBA\Relatorios.

.USO
    Diagnostico somente leitura:
        .\Gerenciar-Inicializacao-Windows.ps1

    Diagnostico com relatorio HTML:
        .\Gerenciar-Inicializacao-Windows.ps1 -GerarHtml

    Modo assistido para modificacoes:
        .\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido

    Simulacao sem alterar o sistema:
        .\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido -DryRun

.NOTAS
    Requer PowerShell 5.1 ou superior.
    Modificacoes em itens de nivel Machine exigem execucao como Administrador.
    Modulo WbaToolkit.Startup e WbaToolkit.Core sao carregados automaticamente.
#>
param(
    [ValidateSet('Diagnostico', 'Assistido')]
    [string]$Modo = 'Diagnostico',

    [switch]$DryRun,

    [switch]$GerarHtml,

    [Alias('DiretorioSaida')]
    [string]$Path
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null } catch { }

$ScriptVersion = 'v1.0'
$ToolkitRoot   = Split-Path -Parent $PSScriptRoot

$coreModulePath    = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$startupModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Startup/WbaToolkit.Startup.psd1'

Import-Module $coreModulePath    -Force -ErrorAction Stop
Import-Module $startupModulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Maintenance; Related=Diagnostico-Reparo-HD100.ps1; Manual=Gerenciamento de inicializacao do Windows

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$script:Session  = $null
$script:Changes  = [System.Collections.ArrayList]::new()

# ─── helpers locais ──────────────────────────────────────────────────────────

function Write-WinStartupLog {
    [CmdletBinding()]
    param(
        [string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )
    $logPath = if ($script:Session) { Join-Path $script:Session.LogsPath 'inicializacao.log' } else { $null }
    Write-ScriptLog -Message $Message -Level $Level -LogPath $logPath
}

function Add-WinStartupChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)]$Item,
        [string]$PreviousState,
        [string]$NewState,
        [bool]$Reversible
    )

    $null = $script:Changes.Add([pscustomobject]@{
        DataHora       = Get-Date
        Acao           = $Action
        Alvo           = $Item.Name
        Tipo           = $Item.SourceType
        Local          = $Item.Location
        EstadoAnterior = $PreviousState
        EstadoNovo     = $NewState
        Reversivel     = $Reversible
    })
}

function Write-WinStartupSection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Host ''
    Write-Host ('--- ' + $Title + ' ---') -ForegroundColor DarkCyan
    Write-WinStartupLog -Message $Title
}

# ─── exportacao de relatorio ─────────────────────────────────────────────────

function Export-WinStartupReportText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$OutPath
    )

    $startupItems  = @($Snapshot.StartupItems)
    $services      = @($Snapshot.Services)
    $changes       = @($Snapshot.Changes)
    $onCount       = @($startupItems | Where-Object { $_.Enabled -eq $true }).Count
    $offCount      = @($startupItems | Where-Object { $_.Enabled -eq $false }).Count

    $startupRows = @($startupItems | ForEach-Object {
        "{0,-4} {1,-3} {2,-14} {3,-12} {4}" -f '', $(if ($_.Enabled) { 'ON' } else { 'OFF' }), $_.SourceType, $_.Scope, $_.Name
    }) -join "`n"

    $serviceRows = @($services | ForEach-Object {
        "{0,-20} {1,-10} {2,-10} {3}" -f $_.Name, $_.Status, $_.StartType, $_.DisplayName
    }) -join "`n"

    $changeRows = if ($changes.Count -gt 0) {
        @($changes | ForEach-Object {
            "[{0}] {1}: {2} ({3} -> {4})" -f ($_.DataHora.ToString('HH:mm:ss')), $_.Acao, $_.Alvo, $_.EstadoAnterior, $_.EstadoNovo
        }) -join "`n"
    }
    else { 'Nenhuma alteracao realizada.' }

    $content = @"
================================================================================
  WBA Windows Toolkit - Gerenciamento de Inicializacao
  Versao: $ScriptVersion
  Inicio: $($Snapshot.StartedAt)
  Fim: $($Snapshot.FinishedAt)
  Modo: $($Snapshot.Modo)
  DryRun: $($Snapshot.DryRun)
  Host: $($Snapshot.ComputerName)
================================================================================

ITENS DE INICIALIZACAO
  Total: $($startupItems.Count) | Ativos: $onCount | Inativos: $offCount

$startupRows

SERVICOS
  Nome                 Status     Inicio     DisplayName
$serviceRows

ALTERACOES DA SESSAO
$changeRows

================================================================================
"@

    [System.IO.File]::WriteAllText(
        $OutPath,
        $content,
        [System.Text.UTF8Encoding]::new($true)
    )

    return $OutPath
}

# ─── execucao principal ───────────────────────────────────────────────────────

Write-Title "WBA Windows Toolkit - Gerenciamento de Inicializacao v$ScriptVersion"

if ($DryRun) { Write-Warn 'MODO DRY-RUN: nenhuma alteracao sera feita no sistema.' }

$script:Session = Initialize-ToolkitReportSession -ModuleName 'WbaToolkit.Startup' -ReportsRoot $Path

Write-WinStartupLog -Message "Sessao iniciada. Modo: $Modo. DryRun: $DryRun."
Write-Info "Relatorios em: $($script:Session.Path)"

# ─── coleta de dados ──────────────────────────────────────────────────────────

Write-WinStartupSection 'Coletando itens de inicializacao'
$startupItems = @(Get-StartupItem)
Write-Info "$(@($startupItems).Count) itens encontrados."

Write-WinStartupSection 'Coletando estado dos servicos'
$services = @(Get-ServiceStartupState)

# ─── exibicao ────────────────────────────────────────────────────────────────

Show-StartupItem -Items $startupItems

Write-Host 'Servicos relevantes:' -ForegroundColor Cyan
foreach ($svc in $services) {
    $color = switch ($svc.Status) {
        'Running' { 'Green' }
        'Stopped' { 'DarkGray' }
        default   { 'Yellow' }
    }
    Write-Host ("  {0,-20} {1,-10} {2}" -f $svc.Name, $svc.Status, $svc.StartType) -ForegroundColor $color
}
Write-Host ''

# ─── modo assistido ───────────────────────────────────────────────────────────

if ($Modo -eq 'Assistido') {
    Write-WinStartupSection 'Modo Assistido: gerenciamento interativo'

    $sessionResults = @(Invoke-StartupManager -DryRun:$DryRun)

    foreach ($r in $sessionResults) {
        if ($r.Success -and $r.Message -ne 'DryRun.') {
            $originalItem = @($startupItems) | Where-Object { $_.Name -eq $r.Name } | Select-Object -First 1
            if ($originalItem) {
                $prevState = switch ($r.Action) {
                    'Disable' { 'On' }
                    'Enable'  { 'Off' }
                    'Remove'  { $originalItem.State }
                }
                $newState = switch ($r.Action) {
                    'Disable' { 'Off' }
                    'Enable'  { 'On' }
                    'Remove'  { 'Removido' }
                }
                $reversible = $r.Action -ne 'Remove'

                Add-WinStartupChange `
                    -Action "$($r.Action)Inicializacao" `
                    -Item $originalItem `
                    -PreviousState $prevState `
                    -NewState $newState `
                    -Reversible $reversible
            }
        }
        Write-WinStartupLog -Level (if ($r.Success) { 'INFO' } else { 'WARN' }) `
            -Message "$($r.Action) '$($r.Name)': $($r.Message)"
    }

    $startupItems = @(Get-StartupItem)
}

# ─── exportacao ───────────────────────────────────────────────────────────────

Write-WinStartupSection 'Exportando relatorio'

$snapshot = [pscustomobject]@{
    StartedAt    = $script:Session.ExecutionName
    FinishedAt   = Get-Date
    Modo         = $Modo
    DryRun       = [bool]$DryRun
    ComputerName = $env:COMPUTERNAME
    StartupItems = @($startupItems)
    Services     = @($services)
    Changes      = @($script:Changes)
}

$txtPath  = Join-Path $script:Session.Path 'relatorio-inicializacao.txt'
$jsonPath = Join-Path $script:Session.Path 'relatorio-inicializacao.json'

Export-WinStartupReportText -Snapshot $snapshot -OutPath $txtPath | Out-Null
$snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath

if ($script:Changes.Count -gt 0) {
    $changesPath = Join-Path $script:Session.Path 'alteracoes.json'
    @($script:Changes) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $changesPath
    Write-Info "Registro de alteracoes: $changesPath"
}

Write-WinStartupLog -Message 'Relatorio exportado.'
Write-Ok "Relatorio TXT: $txtPath"
Write-Ok "Relatorio JSON: $jsonPath"

Write-Host ''
Write-Title "Sessao concluida: $($script:Session.Path)"
