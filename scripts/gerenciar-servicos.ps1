<#
.SYNOPSIS
    Gerenciamento de servicos Windows: listar, iniciar, parar, reiniciar e configurar.

.DESCRIPTION
    Gerencia servicos Windows de forma padronizada.
    Suporta: diagnostico, listagem, inicio, parada, reinicio, alteracao de
    inicializacao (Automatic/Manual/Disabled), alteracao de conta de logon e
    detalhes de servicos.

.PARAMETER Acao
    Acao a executar: Diagnostico (padrao), Listar, Iniciar, Parar, Reiniciar,
    ConfigurarInicializacao, ConfigurarConta, Detalhar.

.PARAMETER Servico
    Nome do servico para operacoes especificas.

.PARAMETER StartupType
    Tipo de inicializacao para ConfigurarInicializacao: Automatic, Manual, Disabled.

.PARAMETER Conta
    Conta de logon para ConfigurarConta. Built-in: LocalSystem, LocalService, NetworkService.

.PARAMETER Senha
    Senha da conta (necessario para contas de dominio).

.PARAMETER DryRun
    Simula a acao sem executar.

.PARAMETER GerarHtml
    Gera relatorio HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatorio ao final (HTML se -GerarHtml, senao TXT).

.PARAMETER Path
    Diretorio raiz de relatorios.

.PARAMETER Help
    Exibe a ajuda e encerra.

.EXAMPLE
    .\gerenciar-servicos.ps1

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Listar

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Parar -Servico Spooler

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao ConfigurarInicializacao -Servico WSearch -StartupType Disabled

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Detalhar -Servico W32Time

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.Services
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Listar', 'Iniciar', 'Parar', 'Reiniciar',
                 'ConfigurarInicializacao', 'ConfigurarConta', 'Detalhar')]
    [string]$Acao = 'Diagnostico',

    [string]$Servico,

    [ValidateSet('Automatic', 'Manual', 'Disabled')]
    [string]$StartupType,

    [string]$Conta,

    [string]$Senha,

    [switch]$DryRun,

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

try { chcp 65001 | Out-Null } catch { }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $PSScriptRoot

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$actionRequiresAdmin = @('Iniciar', 'Parar', 'Reiniciar', 'ConfigurarInicializacao', 'ConfigurarConta')
if ($Acao -in $actionRequiresAdmin -and -not (Test-IsAdministrator)) {
    Write-Warning "A acao '$Acao' exige privilegios administrativos. Solicitando elevacao..."
    $command = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) -Verb RunAs
    exit 0
}

$CoreModulePath    = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$ServicesModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Services/WbaToolkit.Services.psd1'

foreach ($mod in @($CoreModulePath, $ServicesModulePath)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        exit 1
    }
}

try {
    Import-Module $CoreModulePath    -Force -ErrorAction Stop
    Import-Module $ServicesModulePath -Force -ErrorAction Stop
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos do toolkit." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'servicos'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Title "Gerenciamento de Servicos Windows"

if ($DryRun) {
    Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
    Write-Host ""
}

# ── Validacoes ─────────────────────────────────────────────────────────────

if ($Acao -in @('Iniciar', 'Parar', 'Reiniciar', 'ConfigurarInicializacao', 'ConfigurarConta', 'Detalhar')) {
    if ([string]::IsNullOrWhiteSpace($Servico)) {
        Write-Host "[FALHA] Acao '$Acao' requer -Servico." -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

if ($Acao -eq 'ConfigurarInicializacao' -and [string]::IsNullOrWhiteSpace($StartupType)) {
    Write-Host "[FALHA] Acao 'ConfigurarInicializacao' requer -StartupType." -ForegroundColor Red
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

if ($Acao -eq 'ConfigurarConta' -and [string]::IsNullOrWhiteSpace($Conta)) {
    Write-Host "[FALHA] Acao 'ConfigurarConta' requer -Conta." -ForegroundColor Red
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

# ── Diagnostico ────────────────────────────────────────────────────────────

if ($Acao -eq 'Diagnostico') {
    Write-Section "Diagnostico de Servicos"

    $result = Invoke-ServiceManager -Acao Diagnostico

    Write-Host ""
    if ($result.StoppedAuto.Count -gt 0) {
        Write-Warn "$($result.StoppedAuto.Count) servico(s) automatico(s) parado(s):"
        foreach ($s in $result.StoppedAuto) {
            Write-Host "  - $($s.Name) ($($s.DisplayName))" -ForegroundColor Yellow
        }
    }
    else {
        Write-Ok "Todos os servicos automaticos estao em execucao."
    }

    Write-Host ""
    Write-Ok "Diagnostico concluido: $($result.Message)"
}

# ── Listar ─────────────────────────────────────────────────────────────────

if ($Acao -eq 'Listar') {
    Write-Section "Servicos Windows"

    $services = @(Get-WindowsServiceStatus)
    Write-Host ""
    Write-Host "  Total: $($services.Count) servicos" -ForegroundColor Cyan
    Write-Host ""

    $running = @($services | Where-Object { $_.Status -eq 'Running' })
    $stopped = @($services | Where-Object { $_.Status -eq 'Stopped' })

    Write-Host "  Em execucao: $($running.Count)" -ForegroundColor Green
    Write-Host "  Parados:     $($stopped.Count)" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "  Servicos em execucao:" -ForegroundColor Green
    foreach ($s in ($running | Sort-Object Name | Select-Object -First 30)) {
        Write-Host "    $($s.Name) ($($s.DisplayName))" -ForegroundColor Gray
    }
    if ($running.Count -gt 30) {
        Write-Host "    ... e mais $($running.Count - 30)" -ForegroundColor DarkGray
    }
}

# ── Detalhar ───────────────────────────────────────────────────────────────

if ($Acao -eq 'Detalhar') {
    Write-Section "Detalhe: $Servico"

    $detail = Get-WindowsServiceDetail -Name $Servico

    if (-not $detail.Success) {
        Write-Fail $detail.Message
    }
    else {
        Write-Host ""
        $statusColor = switch ($detail.Status) {
            'Running' { 'Green' }
            'Stopped' { 'Yellow' }
            default   { 'Red' }
        }
        Write-Host "  Nome:         $($detail.Name)" -ForegroundColor Cyan
        Write-Host "  Display:      $($detail.DisplayName)"
        Write-Host "  Status:       " -NoNewline
        Write-Host "$($detail.Status)" -ForegroundColor $statusColor
        Write-Host "  Inicializacao:$($detail.StartType)"
        Write-Host "  Conta:        $($detail.Account)"
        Write-Host "  PID:          $($detail.ProcessId)"
        Write-Host "  Caminho:      $($detail.Path)"
        Write-Host "  Descricao:    $($detail.Description)"

        if ($detail.DependentCount -gt 0) {
            Write-Host "  Depende de:   $($detail.DependentServices -join ', ')" -ForegroundColor DarkGray
        }
        if ($detail.RequiredCount -gt 0) {
            Write-Host "  Requer:       $($detail.RequiredServices -join ', ')" -ForegroundColor DarkGray
        }
    }
}

# ── Acoes de CRUD ──────────────────────────────────────────────────────────

switch ($Acao) {
    'Iniciar' {
        Write-Section "Iniciando: $Servico"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Start-Service $Servico" -ForegroundColor Yellow
        }
        else {
            $result = Start-WindowsService -Name $Servico
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'Parar' {
        Write-Section "Parando: $Servico"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Stop-Service $Servico" -ForegroundColor Yellow
        }
        else {
            $result = Stop-WindowsService -Name $Servico
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'Reiniciar' {
        Write-Section "Reiniciando: $Servico"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Stop-Service $Servico; Start-Service $Servico" -ForegroundColor Yellow
        }
        else {
            $result = Restart-WindowsService -Name $Servico
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'ConfigurarInicializacao' {
        Write-Section "Configurando inicializacao: $Servico -> $StartupType"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Set-Service $Servico -StartupType $StartupType" -ForegroundColor Yellow
        }
        else {
            $result = Set-WindowsServiceStartup -Name $Servico -StartupType $StartupType
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'ConfigurarConta' {
        Write-Section "Configurando conta: $Servico -> $Conta"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Change $Servico StartName=$Conta" -ForegroundColor Yellow
        }
        else {
            $params = @{ Name = $Servico; Account = $Conta }
            if ($Senha) { $params['Password'] = $Senha }
            $result = Set-WindowsServiceAccount @params
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }
}

# ── Relatorios ─────────────────────────────────────────────────────────────

$jsonReport = $null
$htmlReport = $null

if ($Acao -in @('Diagnostico', 'Listar', 'Detalhar')) {
    $reportData = switch ($Acao) {
        'Diagnostico' { Invoke-ServiceManager -Acao Diagnostico }
        'Listar'      { @(Get-WindowsServiceStatus) }
        'Detalhar'    { Get-WindowsServiceDetail -Name $Servico }
    }

    $jsonPath = Join-Path $ReportSession.Path "servicos-$($Acao.ToLower()).json"
    $reportData | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $jsonReport = $jsonPath
    Write-Host ""
    Write-Ok "Relatorio: $jsonPath"

    if ($GerarHtml) {
        $htmlPath = Join-Path $ReportSession.Path "servicos-$($Acao.ToLower()).html"

        $bodyHtml = switch ($Acao) {
            'Diagnostico' {
                $diag = $reportData
                @"
<h2>Resumo</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Em Execucao</th><th>Auto Parados</th><th>Desabilitados</th></tr>
<tr>
    <td style="background-color:#d4edda">$($diag.RunningCount)</td>
    <td style="background-color:#fff3cd">$($diag.StoppedAuto.Count)</td>
    <td style="background-color:#f8d7da">$($diag.DisabledCount)</td>
</tr>
</table>

<h2>Servicos Automaticos Parados ($($diag.StoppedAuto.Count))</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Nome</th><th>DisplayName</th><th>Status</th></tr>
$($diag.StoppedAuto | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.DisplayName)</td><td style='background-color:#fff3cd'>$($_.Status)</td></tr>"
} | Out-String)
</table>
"@
            }

            'Listar' {
                $all = $reportData
                $running = @($all | Where-Object { $_.Status -eq 'Running' })
                $stopped = @($all | Where-Object { $_.Status -eq 'Stopped' })
                $other   = @($all | Where-Object { $_.Status -notin @('Running', 'Stopped') })
                @"
<h2>Resumo</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Total</th><th>Em Execucao</th><th>Parados</th><th>Outros</th></tr>
<tr>
    <td>$($all.Count)</td>
    <td style="background-color:#d4edda">$($running.Count)</td>
    <td style="background-color:#fff3cd">$($stopped.Count)</td>
    <td>$($other.Count)</td>
</tr>
</table>

<h2>Servicos em Execucao ($($running.Count))</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Nome</th><th>DisplayName</th><th>StartType</th></tr>
$($running | Sort-Object Name | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.DisplayName)</td><td>$($_.StartType)</td></tr>"
} | Out-String)
</table>

<h2>Servicos Parados ($($stopped.Count))</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Nome</th><th>DisplayName</th><th>StartType</th></tr>
$($stopped | Sort-Object Name | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.DisplayName)</td><td>$($_.StartType)</td></tr>"
} | Out-String)
</table>
"@
            }

            'Detalhar' {
                $d = $reportData
                $statusColor = switch ($d.Status) { 'Running' { '#d4edda' } 'Stopped' { '#fff3cd' } default { '#f8d7da' } }
                @"
<h2>Detalhe: $($d.Name)</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Propriedade</th><th>Valor</th></tr>
<tr><td>Nome</td><td>$($d.Name)</td></tr>
<tr><td>DisplayName</td><td>$($d.DisplayName)</td></tr>
<tr><td>Status</td><td style="background-color:$statusColor">$($d.Status)</td></tr>
<tr><td>Inicializacao</td><td>$($d.StartType)</td></tr>
<tr><td>Conta</td><td>$($d.Account)</td></tr>
<tr><td>PID</td><td>$($d.ProcessId)</td></tr>
<tr><td>Caminho</td><td style="word-break:break-all">$($d.Path)</td></tr>
<tr><td>Descricao</td><td>$($d.Description)</td></tr>
</table>

$(if ($d.DependentCount -gt 0) {
@"
<h2>Servicos que dependem de $($d.Name) ($($d.DependentCount))</h2>
<ul>$($d.DependentServices | ForEach-Object { "<li>$_</li>" } | Out-String)</ul>
"@
})

$(if ($d.RequiredCount -gt 0) {
@"
<h2>Servicos requeridos por $($d.Name) ($($d.RequiredCount))</h2>
<ul>$($d.RequiredServices | ForEach-Object { "<li>$_</li>" } | Out-String)</ul>
"@
})
"@
            }
        }

        $html = New-ToolkitHtmlReport -Title "Gerenciamento de Servicos" `
            -Subtitle "$Acao - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            -Icon "&#9881;" -Body $bodyHtml -FooterText "Gerado por WBA Windows Toolkit"
        [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($true))
        $htmlReport = $htmlPath
        Write-Ok "HTML: $htmlPath"
    }
}

if ($AbrirRelatorio) {
    $target = if ($htmlReport) { $htmlReport } elseif ($jsonReport) { $jsonReport } else { $null }
    if ($target -and (Test-Path -LiteralPath $target)) { Start-Process $target }
}

if ($transcriptActive) { Stop-Transcript }

Write-Host ""
Write-Ok "Gerenciamento de servicos concluido."
