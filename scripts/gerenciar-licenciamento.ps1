#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnóstico e gerenciamento do ciclo de licenciamento do Windows.

.DESCRIPTION
    Exibe o estado atual do licenciamento (canal, status, grace period, dias
    restantes, hardware context) e permite executar ações de gerenciamento:
    ativação online, instalação de product key, rearm, configuração de KMS
    e restauração a partir de um backup pre-operacional.

    O script é SOMENTE LEITURA por padrão (modo Diagnostico). Ações de
    escrita exigem flags explícitos (-Ativar, -InstalarChave, etc.).

.PARAMETER Acao
    Ação a executar: Diagnostico (padrão), Ativar, InstalarChave, Rearm, DefinirKMS.

.PARAMETER ProductKey
    Product key no formato XXXXX-XXXXX-XXXXX-XXXXX-XXXXX (exigido com -Acao InstalarChave).

.PARAMETER KmsServer
    Endereço do servidor KMS (exigido com -Acao DefinirKMS). Formato: host:porta ou apenas host (porta padrão 1688).

.PARAMETER GerarHtml
    Gera relatório HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatório HTML (ou JSON, se HTML não foi gerado) ao final da execução.

.PARAMETER DryRun
    Simula a ação sem executar. Mostra o que seria feito.

.PARAMETER Path
    Diretório raiz de relatórios. Padrão: configuração persistente ou C:\WBA\Relatorios.

.PARAMETER Help
    Exibe a ajuda resumida do script e encerra.

.EXAMPLE
    .\gerenciar-licenciamento.ps1

.EXAMPLE
    .\gerenciar-licenciamento.ps1 -Acao Ativar

.EXAMPLE
    .\gerenciar-licenciamento.ps1 -Acao InstalarChave -ProductKey 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'

.EXAMPLE
    .\gerenciar-licenciamento.ps1 -Acao DefinirKMS -KmsServer 'kms.empresa.com'

.EXAMPLE
    .\gerenciar-licenciamento.ps1 -Acao Rearm -DryRun

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos:
      - WbaToolkit.Core (obrigatório)
      - WbaToolkit.Licensing (obrigatório)
    ExecutionPolicy necessária: RemoteSigned ou Bypass
#>

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Ativar', 'InstalarChave', 'Rearm', 'DefinirKMS', 'Restaurar')]
    [string]$Acao = 'Diagnostico',

    [string]$ProductKey,

    [string]$KmsServer,

    [string]$BackupPath,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [switch]$DryRun,

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

if ($Acao -in @('Ativar', 'InstalarChave', 'Rearm', 'DefinirKMS', 'Restaurar') -and -not (Test-IsAdministrator)) {
    Write-Warning "A acao '$Acao' exige privilegios administrativos. Solicitando elevacao..."
    $command = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) -Verb RunAs
    exit 0
}

$CoreModulePath    = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$LicensingModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Licensing/WbaToolkit.Licensing.psd1'

foreach ($mod in @($CoreModulePath, $LicensingModulePath)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        exit 1
    }
}

try {
    Import-Module $CoreModulePath      -Force -ErrorAction Stop
    Import-Module $LicensingModulePath -Force -ErrorAction Stop
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos do toolkit." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

# WBA-DOCS: Category=Licensing; Manual=Diagnostico e gerenciamento de licenciamento Windows

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'licenciamento'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Title "Gerenciamento de Licenciamento do Windows"

if ($DryRun) {
    Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
    Write-Host ""
}

# ── Validações de parâmetros ──────────────────────────────────────────────

if ($Acao -eq 'InstalarChave') {
    if ([string]::IsNullOrWhiteSpace($ProductKey)) {
        Write-Host "[FALHA] Acao InstalarChave requer o parametro -ProductKey." -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
    if (-not (Test-ProductKeyFormat -ProductKey $ProductKey)) {
        Write-Host "[FALHA] Formato de product key invalido. Use: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

if ($Acao -eq 'DefinirKMS') {
    if ([string]::IsNullOrWhiteSpace($KmsServer)) {
        Write-Host "[FALHA] Acao DefinirKMS requer o parametro -KmsServer." -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

if ($Acao -eq 'Restaurar') {
    if ([string]::IsNullOrWhiteSpace($BackupPath)) {
        Write-Host "[FALHA] Acao Restaurar requer o parametro -BackupPath." -ForegroundColor Red
        Write-Host "        Informe o caminho do diretorio do backup ou do arquivo license-backup.json." -ForegroundColor Yellow
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

# ── Diagnóstico ───────────────────────────────────────────────────────────

Write-Title "Diagnostico de Licenciamento"

$cycleStatus = Get-LicenseCycleStatus

Write-Host ""
$stateColor = switch ($cycleStatus.State) {
    'Licensed'     { 'Green' }
    'GracePeriod'  { 'Yellow' }
    'GraceExpired' { 'Red' }
    'Notification' { 'Yellow' }
    'NonGenuine'   { 'Red' }
    default        { 'White' }
}
Write-Host "  Estado:        " -NoNewline
Write-Host "$($cycleStatus.State)" -ForegroundColor $stateColor

if ($null -ne $cycleStatus.DaysRemaining) {
    $daysColor = if ($cycleStatus.DaysRemaining -le 3) { 'Red' }
                 elseif ($cycleStatus.DaysRemaining -le 7) { 'Yellow' }
                 else { 'Green' }
    Write-Host "  Dias restantes: " -NoNewline
    Write-Host "$($cycleStatus.DaysRemaining)" -ForegroundColor $daysColor
}

if ($null -ne $cycleStatus.ExpirationDate) {
    Write-Host "  Expira em:     $($cycleStatus.ExpirationDate.ToString('dd/MM/yyyy HH:mm'))"
}

Write-Host "  Canal:         $($cycleStatus.Channel)"
Write-Host "  Rearm:         $($cycleStatus.ReadCount) vez(es) restante(s)"
Write-Host ""

$details = $cycleStatus.Details
if ($details) {
    Write-Host "  Edicao:        $($details.Windows.Edicao)"
    Write-Host "  Product ID:    $($details.Licenca.ProductId)"
    Write-Host "  Partial Key:   $($details.Licenca.PartialProductKey)"
    Write-Host "  Status Code:   $($details.Licenca.StatusCodigo)"

    if ($details.Kms.Servidor) {
        Write-Host "  KMS Server:    $($details.Kms.Servidor):$($details.Kms.Porta)"
    }

    if ($details.Hardware) {
        Write-Host "  HWID:          $($details.Hardware.HwidAtual)"
        if ($null -ne $details.Hardware.HardwareAlterado) {
            $alterado = $details.Hardware.HardwareAlterado
            Write-Host "  HW Alterado:   " -NoNewline
            Write-Host "$alterado" -ForegroundColor $(if ($alterado) { 'Red' } else { 'Green' })
        }
    }
}

Write-Host ""
if ($cycleStatus.Recommendations.Count -gt 0) {
    Write-Host "  Recomendacoes:" -ForegroundColor Cyan
    foreach ($rec in $cycleStatus.Recommendations) {
        Write-Host "    - $rec"
    }
}

# ── Ações ──────────────────────────────────────────────────────────────────

if ($Acao -ne 'Diagnostico') {
    Write-Host ""
    Write-Title "Acao: $Acao"

    if ($Acao -eq 'Restaurar') {
        if ($DryRun) {
            $restoreResult = Restore-LicenseState -BackupPath $BackupPath -DryRun
        }
        else {
            Write-Host "  Salvando backup do estado atual antes da restauracao..." -ForegroundColor Cyan
            $preBackup = Backup-LicenseState -Path $ReportSession.Path
            if ($preBackup.Success) {
                Write-Ok "  Backup pre-restauracao: $($preBackup.BackupPath)"
            }

            $restoreResult = Restore-LicenseState -BackupPath $BackupPath -Force
        }

        if ($restoreResult.Success) {
            Write-Ok "  Restauracao concluida."
            if ($restoreResult.Restored.Count -gt 0) {
                Write-Host "  Restauradas: $($restoreResult.Restored -join ', ')" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [INFO] $($restoreResult.Message)" -ForegroundColor Yellow
        }
    }
    else {
        if (-not $DryRun) {
            Write-Host "  Salvando backup do estado atual..." -ForegroundColor Cyan
            $backup = Backup-LicenseState -Path $ReportSession.Path
            if ($backup.Success) {
                Write-Ok "  Backup salvo em: $($backup.BackupPath)"
            }
            else {
                Write-Warning "  Nao foi possivel salvar o backup. Continuando mesmo assim..."
            }
        }

        $slmgrArgs = switch ($Acao) {
            'Ativar'       { @('/ato') }
            'InstalarChave' { @('/ipk', $ProductKey) }
            'Rearm'        { @('/rearm') }
            'DefinirKMS'   { @('/skms', $KmsServer) }
        }

        if ($DryRun) {
            Write-Host "  DRY-RUN: slmgr.vbs $($slmgrArgs -join ' ')" -ForegroundColor Yellow
            Write-Host "  Nenhuma alteracao aplicada." -ForegroundColor Yellow
        }
        else {
            Write-Host "  Executando: slmgr.vbs $($slmgrArgs -join ' ')" -ForegroundColor Cyan
            $result = Invoke-Slmgr -ArgumentList $slmgrArgs -TimeoutSeconds 120

            if ($result.TimedOut) {
                Write-Host "  [FALHA] Timeout ao executar slmgr.vbs." -ForegroundColor Red
            }
            elseif ($result.ExitCode -eq 0) {
                Write-Ok "  Operacao concluida com sucesso."
                if ($result.Lines.Count -gt 0) {
                    Write-Host ""
                    foreach ($line in $result.Lines) {
                        Write-Host "    $line"
                    }
                }
            }
            else {
                Write-Host "  [FALHA] slmgr.vbs retornou codigo $($result.ExitCode)." -ForegroundColor Red
                if ($result.StdErr) {
                    Write-Host "    Erro: $($result.StdErr)" -ForegroundColor Yellow
                }
                if ($result.Lines.Count -gt 0) {
                    foreach ($line in $result.Lines) {
                        Write-Host "    $line" -ForegroundColor Yellow
                    }
                }
            }
        }
    }

    if ($Acao -ne 'Restaurar' -or $DryRun) {
        Write-Host ""
        Write-Host "  Re-verificando estado apos a acao..." -ForegroundColor Cyan
        $cycleAfter = Get-LicenseCycleStatus
        $stateAfterColor = switch ($cycleAfter.State) {
            'Licensed'     { 'Green' }
            'GracePeriod'  { 'Yellow' }
            'GraceExpired' { 'Red' }
            'Notification' { 'Yellow' }
            'NonGenuine'   { 'Red' }
            default        { 'White' }
        }
        Write-Host "  Estado: " -NoNewline
        Write-Host "$($cycleAfter.State)" -ForegroundColor $stateAfterColor
        if ($null -ne $cycleAfter.DaysRemaining) {
            Write-Host "  Dias restantes: $($cycleAfter.DaysRemaining)"
        }
    }
}

# ── Relatórios ────────────────────────────────────────────────────────────

$jsonPath = Join-Path $ReportSession.Path 'licenciamento.json'
$txtPath  = Join-Path $ReportSession.Path 'licenciamento.txt'

$report = [pscustomobject]@{
    GeneratedAt = (Get-Date)
    ComputerName = $env:COMPUTERNAME
    Action      = $Acao
    DryRun      = $DryRun
    CycleStatus = $cycleStatus
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('WBA Windows Toolkit — Gerenciamento de Licenciamento')
$lines.Add(('Gerado em       : {0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
$lines.Add(('Computador      : {0}' -f $env:COMPUTERNAME))
$lines.Add(('Acao solicitada : {0}' -f $Acao))
$lines.Add(('DryRun          : {0}' -f $DryRun))
$lines.Add('')
$lines.Add('--- Estado do Ciclo de Licenciamento ---')
$lines.Add(('Estado          : {0}' -f $cycleStatus.State))
$lines.Add(('Canal           : {0}' -f $cycleStatus.Channel))
$lines.Add(('Dias restantes  : {0}' -f $(if ($null -ne $cycleStatus.DaysRemaining) { $cycleStatus.DaysRemaining } else { 'N/A' })))
$lines.Add(('Expira em       : {0}' -f $(if ($null -ne $cycleStatus.ExpirationDate) { $cycleStatus.ExpirationDate.ToString('dd/MM/yyyy HH:mm') } else { 'N/A' })))
$lines.Add(('Rearm restantes : {0}' -f $cycleStatus.ReadCount))
$lines.Add('')
$lines.Add('--- Recomendacoes ---')
foreach ($rec in $cycleStatus.Recommendations) { $lines.Add("- $rec") }
$lines.Add('')
$lines.Add('--- Detalhes ---')
if ($details) {
    $lines.Add(('Edicao          : {0}' -f $details.Windows.Edicao))
    $lines.Add(('Product ID      : {0}' -f $details.Licenca.ProductId))
    $lines.Add(('Partial Key     : {0}' -f $details.Licenca.PartialProductKey))
    $lines.Add(('HWID            : {0}' -f $(if ($details.Hardware) { $details.Hardware.HwidAtual } else { 'N/A' })))
}
$lines | Set-Content -LiteralPath $txtPath -Encoding UTF8

Write-Host ""
Write-Ok "Relatorios salvos em: $($ReportSession.Path)"
Write-Host "  JSON: $jsonPath" -ForegroundColor Cyan
Write-Host "  TXT:  $txtPath" -ForegroundColor Cyan

if ($GerarHtml) {
    Write-Host "  HTML: (a implementar)" -ForegroundColor Yellow
}

if ($AbrirRelatorio) {
    if (Test-Path $jsonPath) { Start-Process $jsonPath }
}

if ($transcriptActive) { Stop-Transcript }

Write-Host ""
Write-Ok "Gerenciamento de licenciamento concluido."
