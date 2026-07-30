#Requires -Version 5.1
<#
.SYNOPSIS
    Gerenciamento de copias e pontos de restauracao do sistema.

.DESCRIPTION
    Gerenciamento completo de restore points e backup de dados do usuario:
    criacao, listagem, remocao, restauracao, backup com rsync, historico e saude VSS.

    Inspirado no RestorePointManager. Segue padroes do WBA Windows Toolkit.

.PARAMETER Acao
    Acao a executar: Diagnostico (padrao), CriarPontoRestauracao, ListarPontos,
    Restaurar, RemoverPontos, LimparAntigos, BackupUsuario, RestaurarUsuario,
    HistoricoBackup, LimparBackups, SaudeVss, Configurar.

.PARAMETER Descricao
    Descricao para CriarPontoRestauracao.

.PARAMETER SequenceNumber
    Numero de sequencia do restore point para Restaurar.

.PARAMETER ManterUltimos
    Manter apenas os N mais recentes (para RemoverPontos).

.PARAMETER Dias
    Dias de retencao para LimparAntigos.

.PARAMETER CaminhoDestino
    Caminho de destino para BackupUsuario.

.PARAMETER LimiteRestorePoints
    Config - maximo de restore points.

.PARAMETER RetencaoDias
    Config - dias de retencao.

.PARAMETER DryRun
    Simula a acao sem executar.

.PARAMETER GerarHtml
    Gera relatorio HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatorio ao final.

.PARAMETER Path
    Diretorio raiz de relatorios.

.EXAMPLE
    .\gerenciar-copias.ps1

.EXAMPLE
    .\gerenciar-copias.ps1 -Acao CriarPontoRestauracao -Descricao "Pre-atualizacao"

.EXAMPLE
    .\gerenciar-copias.ps1 -Acao BackupUsuario

.EXAMPLE
    .\gerenciar-copias.ps1 -Acao LimparAntigos -Dias 30 -DryRun

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.Backup
#>

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'CriarPontoRestauracao', 'ListarPontos', 'Restaurar', 'RemoverPontos', 'LimparAntigos', 'BackupUsuario', 'RestaurarUsuario', 'HistoricoBackup', 'LimparBackups', 'SaudeVss', 'Configurar')]
    [string]$Acao = 'Diagnostico',

    [string]$Descricao = 'WBA Toolkit Restore Point',

    [int]$SequenceNumber,

    [int]$ManterUltimos,

    [int]$Dias,

    [string]$CaminhoDestino,

    [int]$LimiteRestorePoints,

    [int]$RetencaoDias,

    [switch]$DryRun,

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
try { chcp 65001 | Out-Null } catch { }

$ScriptName = $MyInvocation.MyCommand.Name
$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $ScriptDir

Import-Module (Join-Path $ToolkitRoot 'modules\WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
Import-Module (Join-Path $ToolkitRoot 'modules\WbaToolkit.Backup\WbaToolkit.Backup.psd1') -Force

if (-not (Test-IsAdministrator)) {
    Write-Warn 'Operacao requer privilegios de Administrador. Reabrindo elevado...'
    $relaunch = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunch) -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'copias'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

try {
    Write-Title "Gerenciamento de Copias e Pontos de Restauracao"
    Write-Host ""

    if ($DryRun) {
        Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
        Write-Host ""
    }

    switch ($Acao) {
        'Diagnostico' {
            Write-Section "Saude do VSS"
            $health = Test-VssHealth
            foreach ($check in $health.Checks) {
                $color = switch ($check.Status) {
                    'OK'    { 'Green' }
                    'AVISO' { 'Yellow' }
                    'FALHA' { 'Red' }
                    default { 'Gray' }
                }
                Write-Host "  [$($check.Status)] $($check.Name): $($check.Detail)" -ForegroundColor $color
            }

            Write-Host ""
            Write-Section "Restore Points"
            $points = Get-RestorePointInfo
            if ($points) {
                foreach ($pt in $points) {
                    Write-Host "  #$(($pt.SequenceNumber).ToString().PadLeft(3)) - $($pt.Description)" -ForegroundColor Cyan
                    Write-Host "         Criado: $($pt.CreationTime) | Tipo: $($pt.RestorePointType)" -ForegroundColor Gray
                }
            } else {
                Write-Info "Nenhum restore point encontrado."
            }

            Write-Host ""
            Write-Section "Configuracao"
            $config = Get-BackupConfiguration
            Write-Host "  Max Restore Points:  $($config.RestorePoints.MaxRestorePoints)" -ForegroundColor Gray
            Write-Host "  Retencao (dias):     $($config.RestorePoints.RetentionDays)" -ForegroundColor Gray
            Write-Host "  Min disco (GB):      $($config.RestorePoints.MinDiskSpaceGB)" -ForegroundColor Gray
            Write-Host "  Backup destino:      $($config.UserBackup.LocalBackupPath)" -ForegroundColor Gray
        }

        'CriarPontoRestauracao' {
            Write-Section "Criando Ponto de Restauracao"
            if ($DryRun) {
                Write-Info "[DRYRUN] Restore point seria criado: $Descricao"
            } else {
                $result = New-RestorePoint -Description $Descricao
                if ($result.Success) {
                    Write-Ok "Restore point criado: $Descricao"
                } else {
                    Write-Fail "Falha: $($result.Error)"
                }
            }
        }

        'ListarPontos' {
            Write-Section "Pontos de Restauracao"
            $points = Get-RestorePointInfo
            if ($points) {
                foreach ($pt in $points) {
                    Write-Host "  #$(($pt.SequenceNumber).ToString().PadLeft(3)) - $($pt.Description)" -ForegroundColor Cyan
                    Write-Host "         Criado: $($pt.CreationTime) | Tipo: $($pt.RestorePointType)" -ForegroundColor Gray
                }
                Write-Host ""
                Write-Info "$($points.Count) restore point(s) encontrado(s)."
            } else {
                Write-Info "Nenhum restore point encontrado."
            }
        }

        'Restaurar' {
            if (-not $SequenceNumber) {
                Write-Fail "Parametro -SequenceNumber obrigatorio."
                return
            }
            Write-Section "Restaurar Sistema para Ponto #$SequenceNumber"
            if ($DryRun) {
                Write-Info "[DRYRUN] Sistema seria restaurado para restore point #$SequenceNumber."
            } else {
                Restore-SystemToPoint -SequenceNumber $SequenceNumber
                Write-Ok "Restauracao agendada. O sistema sera restaurado na proxima reinicializacao."
            }
        }

        'RemoverPontos' {
            Write-Section "Removendo Pontos de Restauracao"
            if ($DryRun) {
                if ($ManterUltimos) {
                    Write-Info "[DRYRUN] Seria mantido apenas os $ManterUltimos mais recentes."
                } else {
                    Write-Info "[DRYRUN] Todos os pontos seriam removidos."
                }
            } else {
                $removeParams = @{}
                if ($ManterUltimos) { $removeParams['KeepLast'] = $ManterUltimos }
                else { $removeParams['All'] = $true }
                Remove-RestorePoint @removeParams
            }
        }

        'LimparAntigos' {
            if (-not $Dias) {
                Write-Fail "Parametro -Dias obrigatorio."
                return
            }
            Write-Section "Limpando Restore Points Antigos (>$Dias dias)"
            if ($DryRun) {
                Write-Info "[DRYRUN] Restore points mais antigos que $Dias dias seriam removidos."
            } else {
                Remove-RestorePoint -OlderThanDays $Dias
            }
        }

        'BackupUsuario' {
            Write-Section "Backup de Dados do Usuario"
            if ($DryRun) {
                Write-Info "[DRYRUN] Backup de dados do usuario seria executado."
            } else {
                $backupParams = @{}
                if ($CaminhoDestino) { $backupParams['BackupPath'] = $CaminhoDestino }
                $result = Backup-UserData @backupParams
                if ($result.AllSuccess) {
                    Write-Ok "Backup concluido com sucesso."
                } else {
                    Write-Fail "Backup concluido com erros."
                }
                Write-Host "    Destino: $($result.BackupPath)" -ForegroundColor Gray
            }
        }

        'RestaurarUsuario' {
            if (-not $CaminhoDestino) {
                Write-Fail "Parametro -CaminhoDestino obrigatorio (caminho do backup a restaurar)."
                return
            }
            Write-Section "Restaurando Dados do Usuario"
            if ($DryRun) {
                Write-Info "[DRYRUN] Dados seriam restaurados de: $CaminhoDestino"
            } else {
                $result = Restore-UserData -BackupPath $CaminhoDestino
                if ($result.AllSuccess) {
                    Write-Ok "Restauracao concluida com sucesso."
                } else {
                    Write-Fail "Restauracao concluida com erros."
                }
            }
        }

        'HistoricoBackup' {
            Write-Section "Historico de Backups"
            $history = Get-BackupHistory
            if ($history) {
                foreach ($h in $history) {
                    $status = if ($h.AllSuccess) { '[OK]' } else { '[FALHA]' }
                    $color = if ($h.AllSuccess) { 'Green' } else { 'Red' }
                    Write-Host "  $status $($h.CreatedAt) - $($h.BackupPath)" -ForegroundColor $color
                }
                Write-Host ""
                Write-Info "$($history.Count) backup(s) encontrado(s)."
            } else {
                Write-Info "Nenhum backup encontrado no historico."
            }
        }

        'LimparBackups' {
            if (-not $Dias) {
                Write-Fail "Parametro -Dias obrigatorio."
                return
            }
            Write-Section "Limpando Backups Antigos (>$Dias dias)"
            if ($DryRun) {
                Write-Info "[DRYRUN] Backups mais antigos que $Dias dias seriam removidos."
            } else {
                Remove-BackupAntigo -Days $Dias
            }
        }

        'SaudeVss' {
            Write-Section "Saude do VSS"
            $health = Test-VssHealth
            foreach ($check in $health.Checks) {
                $color = switch ($check.Status) {
                    'OK'    { 'Green' }
                    'AVISO' { 'Yellow' }
                    'FALHA' { 'Red' }
                    default { 'Gray' }
                }
                Write-Host "  [$($check.Status)] $($check.Name): $($check.Detail)" -ForegroundColor $color
            }
            Write-Host ""
            if ($health.Healthy) {
                Write-Ok "Sistema VSS saudavel."
            } else {
                Write-Warn "Sistema VSS com problemas. Verifique os checks acima."
            }
        }

        'Configurar' {
            Write-Section "Configuracao de Backup"
            $settings = @{}
            if ($LimiteRestorePoints -gt 0 -or $RetencaoDias -gt 0) {
                $rpSettings = @{}
                if ($LimiteRestorePoints -gt 0) { $rpSettings['MaxRestorePoints'] = $LimiteRestorePoints }
                if ($RetencaoDias -gt 0) { $rpSettings['RetentionDays'] = $RetencaoDias }
                $settings['RestorePoints'] = $rpSettings
            }

            if ($settings.Count -gt 0) {
                if ($DryRun) {
                    Write-Info "[DRYRUN] Configuracao seria atualizada."
                } else {
                    Set-BackupConfiguration -Settings $settings
                    Write-Ok "Configuracao atualizada."
                }
            }

            $config = Get-BackupConfiguration
            Write-Host ""
            Write-Host "  Configuracao atual:" -ForegroundColor Cyan
            Write-Host "    Max Restore Points: $($config.RestorePoints.MaxRestorePoints)" -ForegroundColor Gray
            Write-Host "    Retencao (dias):    $($config.RestorePoints.RetentionDays)" -ForegroundColor Gray
            Write-Host "    Backup destino:     $($config.UserBackup.LocalBackupPath)" -ForegroundColor Gray
        }
    }

    Write-Host ""

    $jsonReport = Join-Path $ReportSession.Path 'copias-status.json'
    [pscustomobject]@{
        GeneratedAt    = Get-Date
        Acao          = $Acao
        Health        = Test-VssHealth
        RestorePoints = @(Get-RestorePointInfo)
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReport -Encoding UTF8
    Write-Ok "Relatorio: $jsonReport"

    if ($GerarHtml) {
        $htmlPath = Join-Path $ReportSession.Path 'copias.html'
        $health = Test-VssHealth
        $points = Get-RestorePointInfo
        $bodyHtml = @"
<h2>Saude do VSS</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Status</th><th>Check</th><th>Detalhe</th></tr>
$($health.Checks | ForEach-Object {
    $color = switch ($_.Status) { 'OK' { '#d4edda' } 'AVISO' { '#fff3cd' } 'FALHA' { '#f8d7da' } default { '#e2e3e5' } }
    "<tr style='background-color:$color'><td>$($_.Status)</td><td>$($_.Name)</td><td>$($_.Detail)</td></tr>"
} | Out-String)
</table>

<h2>Restore Points ($($points.Count))</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>#</th><th>Descricao</th><th>Data</th><th>Tipo</th></tr>
$($points | ForEach-Object {
    "<tr><td>$($_.SequenceNumber)</td><td>$($_.Description)</td><td>$($_.CreationTime)</td><td>$($_.RestorePointType)</td></tr>"
} | Out-String)
</table>
"@
        $html = New-ToolkitHtmlReport -Title "Copias e Pontos de Restauracao" `
            -Subtitle "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            -Icon "&#128190;" -Body $bodyHtml -FooterText "Gerado por WBA Windows Toolkit"
        [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($true))
        Write-Ok "HTML: $htmlPath"

        if ($AbrirRelatorio) { Start-Process $htmlPath }
    }

    Write-Host ""
    Write-Ok "Gerenciamento de copias concluido."

} catch {
    Write-Fail "Erro: $($_.Exception.Message)"
} finally {
    if ($transcriptActive) { Stop-Transcript }
}
