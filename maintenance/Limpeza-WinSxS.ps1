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

.EXAMPLE
    .\Limpeza-WinSxS.ps1

.EXAMPLE
    .\Limpeza-WinSxS.ps1 -Modo Relatorio -GerarHtml

.EXAMPLE
    .\Limpeza-WinSxS.ps1 -Modo Limpeza -DryRun

.EXAMPLE
    .\Limpeza-WinSxS.ps1 -Modo Limpeza -ResetBase

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\Limpeza-WinSxS.ps1 -Modo Limpeza

.NOTAS
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
    [string]$Path
)

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

$ScriptVersion = 'v1.0'
$ScriptName    = $MyInvocation.MyCommand.Name

if (-not (Test-IsAdministrator)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        } else {
            "-$($kv.Key)"; "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'Maintenance'
$LogDir   = $ReportSession.LogsPath
$LogFile  = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$([System.IO.Path]::GetFileNameWithoutExtension($ScriptName)).log"

$transcriptActive = $false
try {
    Start-Transcript -Path $LogFile -Encoding UTF8 -ErrorAction Stop
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

        $infoExport = [pscustomobject]@{
            Computador         = $env:COMPUTERNAME
            Data               = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
            VersaoScript       = $ScriptVersion
            StoreSizeGB        = $info.StoreSizeGB
            ReclaimableSizeGB  = $info.ReclaimableSizeGB
            RecommendedCleanup = $info.RecommendedCleanup
            LastAnalysisDate   = $info.LastAnalysisDate
            ExitCode           = $info.ExitCode
        }

        $infoExport | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-Ok "Relatorio JSON: $jsonPath"

        if ($GerarHtml) {
            $htmlPath = Join-Path $ReportSession.Path "$baseName.html"
            $rows     = $infoExport.PSObject.Properties |
                ForEach-Object { "<tr><td>$([System.Web.HttpUtility]::HtmlEncode($_.Name))</td><td>$([System.Web.HttpUtility]::HtmlEncode($_.Value))</td></tr>" }
            $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>WinSxS — $($env:COMPUTERNAME)</title>
<style>
body { font-family: Consolas, monospace; margin: 2em; }
h2   { color: #2c3e50; }
table { border-collapse: collapse; width: 60%; }
td, th { border: 1px solid #ccc; padding: .5em .8em; }
th { background: #2c3e50; color: #fff; }
tr:nth-child(even) { background: #f5f5f5; }
</style>
</head>
<body>
<h2>Analise do Component Store — $($env:COMPUTERNAME)</h2>
<table>
<tr><th>Campo</th><th>Valor</th></tr>
$($rows -join "`n")
</table>
</body>
</html>
"@
            $html | Out-File -FilePath $htmlPath -Encoding UTF8
            Write-Ok "Relatorio HTML : $htmlPath"
        }

        Write-Ok "Relatorio concluido. Nenhuma alteracao realizada."
    }
}

if ($transcriptActive) { Stop-Transcript }
