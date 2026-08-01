<#
.SYNOPSIS
    Gerenciamento de copias de sombra (Volume Shadow Copy).

.DESCRIPTION
    Diagnostico e gerenciamento completo de shadow copies (VSS):
    criacao, remocao, configuracao de espaco e protecao do sistema.

    Modo Diagnostico (padrao): Somente leitura, exibe status.
    Acoes de escrita: Criar, Remover, RemoverTodas, ConfigurarEspaco, etc.

.PARAMETER Acao
    Acao a executar: Diagnostico (padrao), Criar, Remover, RemoverTodas,
    ConfigurarEspaco, HabilitarProtecao, DesabilitarProtecao.

.PARAMETER VerificarProtecao
    Exibe somente o status da protecao do sistema (VSS) e encerra.

.PARAMETER ListarCopias
    Lista as copias de sombra existentes e encerra.

.PARAMETER Volume
    Volume alvo (ex: C:). Padrao: C:.

.PARAMETER ShadowCopyId
    ID do shadow copy para Remover individual.

.PARAMETER LimiteGB
    Limite de espaco em GB para ConfigurarEspaco.

.PARAMETER Percentual
    Limite de espaco como percentual para ConfigurarEspaco.

.PARAMETER DryRun
    Simula a acao sem executar.

.PARAMETER GerarHtml
    Gera relatorio HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatorio ao final.

.PARAMETER Path
    Diretorio raiz de relatorios.

.EXAMPLE
    .\gerenciar-copia-sombra.ps1

.EXAMPLE
    .\gerenciar-copia-sombra.ps1 -VerificarProtecao

.EXAMPLE
    .\gerenciar-copia-sombra.ps1 -ListarCopias

.EXAMPLE
    .\gerenciar-copia-sombra.ps1 -Acao Criar

.EXAMPLE
    .\gerenciar-copia-sombra.ps1 -Acao ConfigurarEspaco -LimiteGB 10

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.ShadowCopy
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Criar', 'Remover', 'RemoverTodas', 'ConfigurarEspaco', 'HabilitarProtecao', 'DesabilitarProtecao')]
    [string]$Acao = 'Diagnostico',

    [switch]$VerificarProtecao,

    [switch]$ListarCopias,

    [string]$Volume = 'C:',

    [string]$ShadowCopyId,

    [double]$LimiteGB,

    [double]$Percentual,

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
try { chcp 65001 | Out-Null }
catch { Write-Verbose "Nao foi possivel ajustar a pagina de codigo do console para UTF-8: $($_.Exception.Message)" }

$ScriptName = $MyInvocation.MyCommand.Name
$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $ScriptDir

# === Dependencias: validar e carregar modulos do toolkit ===
$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$vssModuleRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.ShadowCopy'

foreach ($mod in @($coreModuleRoot, $vssModuleRoot)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        Write-Host "        Solucao: verifique o clone do repositorio em $ToolkitRoot" -ForegroundColor Yellow
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot, $vssModuleRoot)) {
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

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'copia-sombra'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

try {
    Write-Title "Gerenciamento de Copia de Sombra (VSS)"
    Write-Host ""

    if ($DryRun) {
        Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
        Write-Host ""
    }

    $status = @(Get-ShadowCopyProtectionStatus)
    $shadows = @(Get-ShadowCopy)
    $storage = @(Get-ShadowCopyStorage)

    if ($VerificarProtecao) {
        Write-Section "Status da Protecao do Sistema"
        foreach ($s in $status) {
            $color = if ($s.ProtectionEnabled) { 'Green' } else { 'Red' }
            $icon  = if ($s.ProtectionEnabled) { '[ATIVO]' } else { '[INATIVO]' }
            Write-Host "  $icon $($s.Volume) - $($s.Label) ($($s.FileSystem))" -ForegroundColor $color
            Write-Host "       Espaco: $($s.FreeGB) GB livre de $($s.SizeGB) GB" -ForegroundColor Gray
            if ($s.AllocatedGB) {
                Write-Host "       Shadow Storage: $($s.AllocatedGB) GB alocados" -ForegroundColor Gray
            }
        }
        Write-Host ""
        $activeCount = @($status | Where-Object { $_.ProtectionEnabled }).Count
        if ($activeCount -gt 0) {
            Write-Ok "Protecao ativa em $activeCount volume(s)."
        } else {
            Write-Warn "Protecao inativa em todos os volumes."
        }
        return
    }

    if ($ListarCopias) {
        Write-Section "Shadow Copies Existentes ($($shadows.Count))"
        if ($shadows) {
            foreach ($sh in $shadows) {
                Write-Host "  ID: $($sh.ShadowCopyId)" -ForegroundColor Cyan
                Write-Host "    Volume: $($sh.Volume)" -ForegroundColor Gray
                Write-Host "    Criado: $($sh.CreatedAt)" -ForegroundColor Gray
                Write-Host "    Estado: $($sh.State)" -ForegroundColor Gray
                Write-Host ""
            }
            Write-Info "$($shadows.Count) shadow copy(s) encontrado(s)."
        } else {
            Write-Info "Nenhum shadow copy encontrado."
        }
        return
    }

    switch ($Acao) {
        'Diagnostico' {
            Write-Section "Status da Protecao do Sistema"
            foreach ($s in $status) {
                $color = if ($s.ProtectionEnabled) { 'Green' } else { 'Red' }
                $icon  = if ($s.ProtectionEnabled) { '[OK]' } else { '[OFF]' }
                Write-Host "  $icon $($s.Volume) - $($s.Label) ($($s.FileSystem))" -ForegroundColor $color
                Write-Host "       Espaco: $($s.FreeGB) GB livre de $($s.SizeGB) GB" -ForegroundColor Gray
                if ($s.AllocatedGB) {
                    Write-Host "       Shadow Storage: $($s.AllocatedGB) GB alocados" -ForegroundColor Gray
                }
            }

            Write-Host ""
            Write-Section "Shadow Copies Existentes ($($shadows.Count))"
            if ($shadows) {
                foreach ($sh in $shadows) {
                    Write-Host "  ID: $($sh.ShadowCopyId)" -ForegroundColor Cyan
                    Write-Host "    Volume: $($sh.Volume)" -ForegroundColor Gray
                    Write-Host "    Criado: $($sh.CreatedAt)" -ForegroundColor Gray
                    Write-Host "    Estado: $($sh.State)" -ForegroundColor Gray
                    Write-Host ""
                }
            } else {
                Write-Info "Nenhum shadow copy encontrado."
            }

            Write-Host ""
            Write-Section "Uso do Shadow Storage"
            if ($storage) {
                foreach ($st in $storage) {
                    Write-Host "  Volume: $($st.Volume)" -ForegroundColor Cyan
                    Write-Host "    Usado:     $($st.UsedSpace)" -ForegroundColor Gray
                    Write-Host "    Alocado:   $($st.AllocatedSpace)" -ForegroundColor Gray
                    Write-Host "    Maximo:    $($st.MaximumSpace)" -ForegroundColor Gray
                }
            } else {
                Write-Info "Nenhum dado de shadow storage encontrado."
            }
        }

        'Criar' {
            Write-Section "Criando Shadow Copy em $Volume"
            if ($DryRun) {
                Write-Info "[DRYRUN] Seria criado shadow copy em $Volume."
            } else {
                $result = New-ShadowCopy -Volume $Volume
                if ($result) {
                    Write-Ok "Shadow copy criado: $($result.ShadowCopyId)"
                    Write-Host "    Volume: $($result.Volume)" -ForegroundColor Gray
                    Write-Host "    Criado: $($result.CreatedAt)" -ForegroundColor Gray
                } else {
                    Write-Fail "Falha ao criar shadow copy."
                }
            }
        }

        'Remover' {
            if (-not $ShadowCopyId) {
                Write-Fail "Parametro -ShadowCopyId obrigatorio para acao Remover."
                return
            }
            Write-Section "Removendo Shadow Copy"
            if ($DryRun) {
                Write-Info "[DRYRUN] Seria removido shadow copy: $ShadowCopyId"
            } else {
                Remove-ShadowCopy -ShadowCopyId $ShadowCopyId
                Write-Ok "Shadow copy removido."
            }
        }

        'RemoverTodas' {
            Write-Section "Removendo Todas os Shadow Copies"
            if ($DryRun) {
                Write-Info "[DRYRUN] Todos os shadow copies de $Volume seriam removidos."
            } else {
                Remove-ShadowCopy -Volume $Volume
                Write-Ok "Todos os shadow copies de $Volume removidos."
            }
        }

        'ConfigurarEspaco' {
            if ($LimiteGB -le 0 -and $Percentual -le 0) {
                Write-Fail "Parametro -LimiteGB ou -Percentual obrigatorio."
                return
            }
            Write-Section "Configurando Espaco do Shadow Storage"
            if ($DryRun) {
                if ($LimiteGB -gt 0) {
                    Write-Info "[DRYRUN] Limite seria definido: $LimiteGB GB em $Volume"
                } else {
                    Write-Info "[DRYRUN] Limite seria definido: $Percentual% em $Volume"
                }
            } else {
                if ($LimiteGB -gt 0) {
                    Set-ShadowCopyStorageLimit -Volume $Volume -MaxSizeGB $LimiteGB
                } else {
                    Set-ShadowCopyStorageLimit -Volume $Volume -MaxSizePercent $Percentual
                }
                Write-Ok "Limite de shadow storage atualizado em $Volume."
            }
        }

        'HabilitarProtecao' {
            Write-Section "Habilitando Protecao do Sistema em $Volume"
            if ($DryRun) {
                Write-Info "[DRYRUN] Protecao do Sistema seria habilitada em $Volume."
            } else {
                Enable-SystemProtection -Volume $Volume
                Write-Ok "Protecao habilitada em $Volume."
            }
        }

        'DesabilitarProtecao' {
            Write-Section "Desabilitando Protecao do Sistema em $Volume"
            if ($DryRun) {
                Write-Info "[DRYRUN] Protecao do Sistema seria desabilitada em $Volume."
            } else {
                Disable-SystemProtection -Volume $Volume
                Write-Ok "Protecao desabilitada em $Volume."
            }
        }
    }

    Write-Host ""

    $jsonReport = Join-Path $ReportSession.Path 'copia-sombra-status.json'
    [pscustomobject]@{
        GeneratedAt = Get-Date
        Acao       = $Acao
        Volume     = $Volume
        Protection = $status
        Shadows    = @($shadows)
        Storage    = @($storage)
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReport -Encoding UTF8
    Write-Ok "Relatorio: $jsonReport"

    if ($GerarHtml) {
        $htmlPath = Join-Path $ReportSession.Path 'copia-sombra.html'
        $bodyHtml = @"
<h2>Protecao do Sistema</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Volume</th><th>Label</th><th>Protecao</th><th>Livre</th><th>Total</th><th>Shadow Storage</th></tr>
$($status | ForEach-Object {
    $protColor = if ($_.ProtectionEnabled) { '#d4edda' } else { '#f8d7da' }
    "<tr style='background-color:$protColor'><td>$($_.Volume)</td><td>$($_.Label)</td><td>$($_.ProtectionEnabled)</td><td>$($_.FreeGB) GB</td><td>$($_.SizeGB) GB</td><td>$($_.AllocatedGB) GB</td></tr>"
} | Out-String)
</table>

<h2>Shadow Copies ($($shadows.Count))</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>ID</th><th>Volume</th><th>Criado</th><th>Estado</th></tr>
$($shadows | ForEach-Object {
    "<tr><td>$($_.ShadowCopyId)</td><td>$($_.Volume)</td><td>$($_.CreatedAt)</td><td>$($_.State)</td></tr>"
} | Out-String)
</table>
"@
        $html = New-ToolkitHtmlReport -Title "Copia de Sombra (VSS)" `
            -Subtitle "$Volume - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            -Icon "&#128190;" -Body $bodyHtml -FooterText "Gerado por WBA Windows Toolkit"
        [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($true))
        Write-Ok "HTML: $htmlPath"

        if ($AbrirRelatorio) { Start-Process $htmlPath }
    }

    Write-Host ""
    Write-Ok "Gerenciamento de copia de sombra concluido."

} catch {
    Write-Fail "Erro: $($_.Exception.Message)"
} finally {
    if ($transcriptActive) { Stop-Transcript }
}
