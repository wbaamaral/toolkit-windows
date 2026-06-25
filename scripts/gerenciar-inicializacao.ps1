#requires -version 5.1
<#
.SYNOPSIS
    Gerenciamento de itens de inicializacao e servicos do Windows.

.DESCRIPTION
    Ferramenta dedicada ao gerenciamento da inicializacao do Windows. Coleta, exibe
    e permite modificar entradas das tres fontes reconhecidas pelo toolkit:

      - Registro (HKLM/HKCU Run e RunOnce)
      - Pasta de inicializacao (usuario e sistema)
      - Tarefas agendadas com gatilho de logon ou boot

    Adicionalmente, exibe o estado e o tipo de inicializacao dos servicos relevantes.

    No modo Diagnostico (padrao), apenas coleta e exibe informacoes sem alterar nada.
    No modo Assistido, permite ao operador desabilitar, reativar ou remover entradas.

    A coleta, exibicao e modificacao sao delegadas ao modulo WbaToolkit.Startup; o
    script orquestra o fluxo, registra a sessao e exporta relatorios.

    Todas as operacoes de desativacao sao reversiveis: o item original e registrado
    no repositorio WBA (HKLM:\SOFTWARE\WBA\WindowsToolkit\Startup\Disabled) antes
    de qualquer alteracao.

    Os relatorios seguem o padrao global de saida do toolkit. Quando -DiretorioSaida
    nao e informado, o caminho e resolvido pela configuracao persistente (ReportsRoot)
    ou, na ausencia desta, por C:\WBA\Relatorios. Os artefatos sao gravados em
    <Raiz>\WbaToolkit.Startup\<yyyy-MM-dd_HHmmss>\ (relatorio TXT, JSON, alteracoes
    e a pasta logs\).

.PARAMETER Modo
    Define o modo de execucao:
      Diagnostico - leitura e relatorio apenas (padrao)
      Assistido   - permite modificacoes interativas

.PARAMETER DryRun
    Simula todas as operacoes sem efetuar alteracoes no sistema.

.PARAMETER GerarHtml
    Reservado para geracao de relatorio HTML alem do TXT e JSON.

.PARAMETER Path
    Raiz de relatorios escolhida pelo usuario. Quando omitido, usa a configuracao
    persistente do toolkit ou C:\WBA\Relatorios. Aceita o alias -DiretorioSaida.

.EXAMPLE
    .\gerenciar-inicializacao.ps1

    Diagnostico somente leitura (nenhuma alteracao no sistema).

.EXAMPLE
    .\gerenciar-inicializacao.ps1 -GerarHtml

    Diagnostico com relatorio adicional em HTML.

.EXAMPLE
    .\gerenciar-inicializacao.ps1 -Modo Assistido

    Modo assistido para desabilitar, reativar ou remover entradas.

.EXAMPLE
    .\gerenciar-inicializacao.ps1 -Modo Assistido -DryRun

    Simula as modificacoes do modo assistido sem alterar o sistema.

.EXAMPLE
    .\gerenciar-inicializacao.ps1 -DiretorioSaida D:\Relatorios\Cliente01

    Grava os relatorios na raiz informada.

.NOTES
    Requer PowerShell 5.1 ou superior.
    Modificacoes em itens de nivel Machine exigem execucao como Administrador.
    Modulos WbaToolkit.Startup e WbaToolkit.Core sao carregados automaticamente.
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

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

$ScriptVersion = 'v1.0'
$ToolkitRoot   = Split-Path -Parent $PSScriptRoot

$coreModulePath    = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$startupModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Startup/WbaToolkit.Startup.psd1'

Import-Module $coreModulePath    -Force -ErrorAction Stop
Import-Module $startupModulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Startup; Manual=Gerenciamento de inicializacao e servicos do Windows

$ErrorActionPreference = 'Continue'

$script:Session  = $null
$script:Changes  = [System.Collections.ArrayList]::new()

# ─── elevacao para o modo assistido (operacoes de nivel Machine) ───────────────

if ($Modo -eq 'Assistido' -and -not (Test-IsAdministrator)) {
    Write-Warn 'Modo Assistido requer privilegios de Administrador para modificar itens de nivel Machine.'
    Write-Info 'Tentando relancar o script de forma elevada...'

    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        }
        else {
            "-$($kv.Key)"; "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

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

    Write-TextFileUtf8 -Path $OutPath -Content $content
    return $OutPath
}

# ─── execucao principal ───────────────────────────────────────────────────────

Write-Title "WBA Windows Toolkit - Gerenciamento de Inicializacao $ScriptVersion"

if ($DryRun) { Write-Warn 'MODO DRY-RUN: nenhuma alteracao sera feita no sistema.' }

$script:Session = Initialize-ToolkitReportSession -ModuleName 'WbaToolkit.Startup' -ReportsRoot $Path

Write-WinStartupLog -Message "Sessao iniciada. Modo: $Modo. DryRun: $DryRun."
Write-Info "Relatorios em: $($script:Session.Path)"

# ─── coleta de dados ──────────────────────────────────────────────────────────

Write-Section 'Coletando itens de inicializacao'
$startupItems = @(Get-StartupItem)
Write-Info "$(@($startupItems).Count) itens encontrados."

Write-Section 'Coletando estado dos servicos'
$services = @(Get-ServiceStartupState)
Write-Info "$(@($services).Count) servicos consultados."

# ─── exibicao ────────────────────────────────────────────────────────────────

Show-StartupItem -Items $startupItems

Write-Section 'Servicos relevantes'
foreach ($svc in $services) {
    $line = "{0,-20} {1,-10} {2}" -f $svc.Name, $svc.Status, $svc.StartType
    switch ($svc.Status) {
        'Running' { Write-Ok   $line }
        'Stopped' { Write-Info $line }
        default   { Write-Warn $line }
    }
}

# ─── modo assistido ───────────────────────────────────────────────────────────

if ($Modo -eq 'Assistido') {
    Write-Section 'Modo Assistido: gerenciamento interativo'

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
        $logLevel = if ($r.Success) { 'INFO' } else { 'WARN' }
        Write-WinStartupLog -Level $logLevel -Message "$($r.Action) '$($r.Name)': $($r.Message)"
    }

    $startupItems = @(Get-StartupItem)
}

# ─── exportacao ───────────────────────────────────────────────────────────────

Write-Section 'Exportando relatorio'

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
Write-TextFileUtf8 -Path $jsonPath -Content ($snapshot | ConvertTo-Json -Depth 8)

if ($script:Changes.Count -gt 0) {
    $changesPath = Join-Path $script:Session.Path 'alteracoes.json'
    Write-TextFileUtf8 -Path $changesPath -Content (@($script:Changes) | ConvertTo-Json -Depth 6)
    Write-Info "Registro de alteracoes: $changesPath"
}

Write-WinStartupLog -Message 'Relatorio exportado.'
Write-Ok "Relatorio TXT: $txtPath"
Write-Ok "Relatorio JSON: $jsonPath"
Write-Info "Logs: $($script:Session.LogsPath)"

Write-Title "Sessao concluida: $($script:Session.Path)"
