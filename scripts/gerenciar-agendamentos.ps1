<#
.SYNOPSIS
    Gerenciamento de tarefas agendadas (Task Scheduler).

.DESCRIPTION
    Diagnostico e gerenciamento completo de tarefas agendadas:
    listagem, detalhes, execucao, habilitacao, desabilitacao, remocao, export/import.

    Modo Diagnostico (padrao): Exibe resumo geral das tarefas.

.PARAMETER Acao
    Acao a executar: Diagnostico (padrao), Listar, Detalhar, Executar, Habilitar,
    Desabilitar, Remover, Exportar, Importar.

.PARAMETER NomeTarefa
    Nome da tarefa agendada.

.PARAMETER Caminho
    Caminho da pasta de tarefas (para Listar).

.PARAMETER Estado
    Filtrar por estado: Ready, Running, Disabled, All.

.PARAMETER Busca
    Termo de busca para Listar.

.PARAMETER CaminhoSaida
    Caminho do arquivo de saida para Exportar.

.PARAMETER CaminhoXml
    Caminho do arquivo XML para Importar.

.PARAMETER DryRun
    Simula a acao sem executar.

.PARAMETER Silent
    Suprime confirmacoes.

.PARAMETER GerarHtml
    Gera relatorio HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatorio ao final.

.PARAMETER Path
    Diretorio raiz de relatorios.

.EXAMPLE
    .\gerenciar-agendamentos.ps1

.EXAMPLE
    .\gerenciar-agendamentos.ps1 -Acao Listar -Caminho "\Microsoft"

.EXAMPLE
    .\gerenciar-agendamentos.ps1 -Acao Detalhar -NomeTarefa "Backup"

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.ScheduledTask
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Listar', 'Detalhar', 'Executar', 'Habilitar', 'Desabilitar', 'Remover', 'Exportar', 'Importar')]
    [string]$Acao = 'Diagnostico',

    [string]$NomeTarefa,

    [string]$Caminho,

    [ValidateSet('Ready', 'Running', 'Disabled', 'All')]
    [string]$Estado = 'All',

    [string]$Busca,

    [string]$CaminhoSaida,

    [string]$CaminhoXml,

    [switch]$DryRun,

    [switch]$Silent,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Alias('DiretorioSaida')]
    [string]$Path,

    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
try { chcp 65001 | Out-Null }
catch { Write-Verbose "Nao foi possivel ajustar a pagina de codigo do console para UTF-8: $($_.Exception.Message)" }

$ScriptName = $MyInvocation.MyCommand.Name
$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $ScriptDir

# === Dependencias: validar e carregar modulos do toolkit ===
$coreModuleRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$schedModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.ScheduledTask'

foreach ($mod in @($coreModuleRoot, $schedModuleRoot)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        Write-Host "        Solucao: verifique o clone do repositorio em $ToolkitRoot" -ForegroundColor Yellow
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot, $schedModuleRoot)) {
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
    Write-Host "        Solucao: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-IsAdministrator)) {
    Write-Warn 'Operacao requer privilegios de Administrador. Reabrindo elevado...'
    $relaunch = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunch) -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'agendamentos'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

try {
    Write-Title "Gerenciamento de Agendamentos (Task Scheduler)"
    Write-Host ""

    if ($DryRun) {
        Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
        Write-Host ""
    }

    switch ($Acao) {
        'Diagnostico' {
            $summary = Get-ScheduledTaskSummary

            Write-Section "Resumo Geral"
            Write-Host "  Total de tarefas:  $($summary.Total)" -ForegroundColor Cyan
            Write-Host "  Habilitadas:       $($summary.Enabled)" -ForegroundColor Green
            Write-Host "  Desabilitadas:     $($summary.Disabled)" -ForegroundColor Yellow
            Write-Host "  Prontas:           $($summary.Ready)" -ForegroundColor Gray
            Write-Host "  Em execucao:       $($summary.Running)" -ForegroundColor Gray

            Write-Host ""
            Write-Section "Top 10 Pastas"
            foreach ($p in $summary.TopPaths) {
                Write-Host "  $($p.Count.ToString().PadLeft(4))  $($p.Path)" -ForegroundColor Gray
            }

            if ($summary.RecentFailures.Count -gt 0) {
                Write-Host ""
                Write-Section "Ultimas Falhas"
                foreach ($f in $summary.RecentFailures) {
            Write-Fail "$($f.TaskName) (resultado: $($f.LastResult))"
                }
            }
        }

        'Listar' {
            Write-Section "Listando Tarefas Agendadas"
            $findParams = @{ State = $Estado }
            if ($Busca) { $findParams['SearchTerm'] = $Busca }
            if ($Caminho) { $findParams['TaskPath'] = $Caminho }

            $tasks = Find-ScheduledTask @findParams

            if (-not $tasks) {
                Write-Info "Nenhuma tarefa encontrada."
                return
            }

            Write-Host ""
            foreach ($t in $tasks) {
                $stateColor = switch ($t.State) {
                    'Ready'    { 'Green' }
                    'Running'  { 'Cyan' }
                    'Disabled' { 'Yellow' }
                    default    { 'Gray' }
                }
                Write-Host ("  [{0,-9}] {1}" -f $t.State, $t.TaskName) -ForegroundColor $stateColor
                Write-Host ("             Caminho: {0}" -f $t.TaskPath) -ForegroundColor DarkGray
                if ($t.LastRunTime) {
                    Write-Host ("             Ultima execucao: {0} (resultado: {1})" -f $t.LastRunTime, $t.LastResult) -ForegroundColor DarkGray
                }
            }
            Write-Host ""
            Write-Info "$($tasks.Count) tarefa(s) encontrada(s)."
        }

        'Detalhar' {
            if (-not $NomeTarefa) {
                Write-Fail "Parametro -NomeTarefa obrigatorio para acao Detalhar."
                return
            }
            Write-Section "Detalhes da Tarefa: $NomeTarefa"
            $detail = Get-ScheduledTaskDetail -TaskName $NomeTarefa

            Write-Host ""
            Write-Host "  Nome:        $($detail.TaskName)" -ForegroundColor Cyan
            Write-Host "  Caminho:     $($detail.TaskPath)" -ForegroundColor Gray
            Write-Host "  Estado:      $($detail.State)" -ForegroundColor Gray
            Write-Host "  Descricao:   $($detail.Description)" -ForegroundColor Gray
            Write-Host "  Autor:       $($detail.Author)" -ForegroundColor Gray
            Write-Host "  Executa como: $($detail.RunAs)" -ForegroundColor Gray
            Write-Host "  Nivel:       $($detail.RunLevel)" -ForegroundColor Gray
            Write-Host "  Ultima exec: $($detail.LastRunTime)" -ForegroundColor Gray
            Write-Host "  Resultado:   $($detail.LastResult)" -ForegroundColor Gray
            Write-Host "  Proxima exec: $($detail.NextRunTime)" -ForegroundColor Gray

            if ($detail.Actions) {
                Write-Host ""
                Write-Host "  Acoes:" -ForegroundColor Cyan
                foreach ($a in $detail.Actions) {
                    Write-Host "    Execute: $($a.Execute)" -ForegroundColor Gray
                    if ($a.Argument) { Write-Host "    Argumento: $($a.Argument)" -ForegroundColor Gray }
                    if ($a.WorkDir) { Write-Host "    Diretorio: $($a.WorkDir)" -ForegroundColor Gray }
                }
            }

            if ($detail.Triggers) {
                Write-Host ""
                Write-Host "  Triggers:" -ForegroundColor Cyan
                foreach ($tr in $detail.Triggers) {
                    $trigInfo = "    $($tr.Type)"
                    if ($tr.StartBoundary) { $trigInfo += " - Inicio: $($tr.StartBoundary)" }
                    if ($tr.Interval) { $trigInfo += " - Intervalo: $($tr.Interval)" }
                    if ($tr.UserId) { $trigInfo += " - Usuario: $($tr.UserId)" }
                    Write-Host $trigInfo -ForegroundColor Gray
                }
            }
        }

        'Executar' {
            if (-not $NomeTarefa) {
                Write-Fail "Parametro -NomeTarefa obrigatorio para acao Executar."
                return
            }
            Write-Section "Executando Tarefa: $NomeTarefa"
            if ($DryRun) {
                Write-Info "[DRYRUN] Tarefa '$NomeTarefa' seria executada."
            } else {
                Start-ScheduledTaskByName -TaskName $NomeTarefa
                Write-Ok "Tarefa '$NomeTarefa' iniciada."
            }
        }

        'Habilitar' {
            if (-not $NomeTarefa) {
                Write-Fail "Parametro -NomeTarefa obrigatorio para acao Habilitar."
                return
            }
            Write-Section "Habilitando Tarefa: $NomeTarefa"
            if ($DryRun) {
                Write-Info "[DRYRUN] Tarefa '$NomeTarefa' seria habilitada."
            } else {
                Enable-ScheduledTaskByName -TaskName $NomeTarefa
                Write-Ok "Tarefa habilitada."
            }
        }

        'Desabilitar' {
            if (-not $NomeTarefa) {
                Write-Fail "Parametro -NomeTarefa obrigatorio para acao Desabilitar."
                return
            }
            Write-Section "Desabilitando Tarefa: $NomeTarefa"
            if ($DryRun) {
                Write-Info "[DRYRUN] Tarefa '$NomeTarefa' seria desabilitada."
            } else {
                Disable-ScheduledTaskByName -TaskName $NomeTarefa
                Write-Ok "Tarefa desabilitada."
            }
        }

        'Remover' {
            if (-not $NomeTarefa) {
                Write-Fail "Parametro -NomeTarefa obrigatorio para acao Remover."
                return
            }
            Write-Section "Removendo Tarefa: $NomeTarefa"
            if ($DryRun) {
                Write-Info "[DRYRUN] Tarefa '$NomeTarefa' seria removida."
            } else {
                $confirmParam = @{ Confirm = (-not $Silent) }
                Unregister-ScheduledTaskByName -TaskName $NomeTarefa @confirmParam
                Write-Ok "Tarefa removida."
            }
        }

        'Exportar' {
            if (-not $NomeTarefa) {
                Write-Fail "Parametro -NomeTarefa obrigatorio para acao Exportar."
                return
            }
            Write-Section "Exportando Tarefa: $NomeTarefa"
            if ($DryRun) {
                Write-Info "[DRYRUN] Tarefa '$NomeTarefa' seria exportada."
            } else {
                $exportParams = @{ TaskName = $NomeTarefa }
                if ($CaminhoSaida) { $exportParams['OutputPath'] = $CaminhoSaida }
                $exported = Export-ScheduledTaskXml @exportParams
                Write-Ok "Exportada para: $exported"
            }
        }

        'Importar' {
            if (-not $CaminhoXml) {
                Write-Fail "Parametro -CaminhoXml obrigatorio para acao Importar."
                return
            }
            Write-Section "Importando Tarefa de XML"
            if ($DryRun) {
                Write-Info "[DRYRUN] Tarefa de '$CaminhoXml' seria importada."
            } else {
                $importParams = @{ XmlPath = $CaminhoXml }
                if ($NomeTarefa) { $importParams['TaskName'] = $NomeTarefa }
                if ($Caminho) { $importParams['TaskPath'] = $Caminho }
                $imported = Import-ScheduledTaskXml @importParams
                Write-Ok "Importada: $($imported.TaskName)"
            }
        }
    }

    Write-Host ""

    $jsonReport = Join-Path $ReportSession.Path 'agendamentos-status.json'
    [pscustomobject]@{
        GeneratedAt = Get-Date
        Acao       = $Acao
        Resumo     = Get-ScheduledTaskSummary
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReport -Encoding UTF8
    Write-Ok "Relatorio: $jsonReport"

    if ($GerarHtml) {
        $htmlPath = Join-Path $ReportSession.Path 'agendamentos.html'
        $summary = Get-ScheduledTaskSummary
        $bodyHtml = @"
<h2>Resumo Geral</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Total</th><th>Habilitadas</th><th>Desabilitadas</th><th>Prontas</th><th>Executando</th></tr>
<tr><td>$($summary.Total)</td><td>$($summary.Enabled)</td><td>$($summary.Disabled)</td><td>$($summary.Ready)</td><td>$($summary.Running)</td></tr>
</table>

<h2>Top 10 Pastas</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Pasta</th><th>Quantidade</th></tr>
$($summary.TopPaths | ForEach-Object { "<tr><td>$($_.Path)</td><td>$($_.Count)</td></tr>" } | Out-String)
</table>
"@
        $html = New-ToolkitHtmlReport -Title "Agendamentos (Task Scheduler)" `
            -Subtitle "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            -Icon "&#128197;" -Body $bodyHtml -FooterText "Gerado por WBA Windows Toolkit"
        [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($true))
        Write-Ok "HTML: $htmlPath"

        if ($AbrirRelatorio) { Start-Process $htmlPath }
    }

    Write-Host ""
    Write-Ok "Gerenciamento de agendamentos concluido."

} catch {
    Write-Fail "Erro: $($_.Exception.Message)"
} finally {
    if ($transcriptActive) { Stop-Transcript }
}
