#requires -version 5.1
<#
.SYNOPSIS
    Script de limpeza segura, manutenção e otimização conservadora para Windows 10 Pro.

.DESCRIPTION
    Este script executa rotinas administrativas seguras para liberar espaço em disco,
    remover arquivos temporários, limpar logs não essenciais antigos, remover arquivos
    de dump de memória, limpar cache do Windows Update, executar verificações de
    integridade do sistema e aplicar ajustes opcionais de manutenção.

    O foco desta versão é realizar uma limpeza eficiente sem remover componentes
    críticos do Windows.

.FUNCIONALIDADES
    - Cria log completo na pasta padronizada de relatorios do toolkit.
    - Solicita elevação administrativa automaticamente.
    - Coleta espaço livre antes e depois da limpeza.
    - Remove arquivos temporários do usuário atual.
    - Remove arquivos temporários dos perfis locais.
    - Remove arquivos temporários de C:\Windows\Temp.
    - Remove minidumps em C:\Windows\Minidump.
    - Remove C:\Windows\MEMORY.DMP, quando existir.
    - Remove relatórios antigos do Windows Error Reporting.
    - Remove logs antigos não essenciais.
    - Preserva CBS.log ativo.
    - Limpa cache de miniaturas e ícones dos usuários.
    - Limpa cache de download do Windows Update.
    - Executa limpeza integrada do Windows com cleanmgr.
    - Executa SFC e DISM, salvo quando desabilitado por parâmetro.
    - Pode desativar hibernação, liberando espaço do hiberfil.sys.
    - Pode configurar tamanho fixo do arquivo de paginação.
    - Pode executar CompactOS opcionalmente.
    - Pode otimizar o volume C:.
    - Pode reiniciar automaticamente ao final.
    - Verifica eventos de falha no sistema de arquivos e oferece agendamento de chkdsk.
    - Registra evento no Visualizador de Eventos ao agendar chkdsk (fonte: LimpezaWindows).
    - Limpa logs do Visualizador de Eventos com três opções: todos, apenas erros/falhas, ou nenhum.

.IMPACTOS ESPERADOS
    - Liberação de espaço em disco.
    - Remoção de arquivos temporários e resíduos de manutenção.
    - Remoção de dumps antigos de falhas.
    - Redução de cache acumulado do Windows Update.
    - Verificação e possível reparo de arquivos do sistema.
    - Reinicialização pode ser necessária para aplicar algumas alterações.

.O QUE ESTE SCRIPT NÃO REMOVE
    - Não remove C:\Windows\Installer.
    - Não remove manualmente WinSxS.
    - Não remove drivers.
    - Não remove perfis de usuários.
    - Não remove programas instalados.
    - Não remove documentos dos usuários.
    - Não executa limpeza agressiva de registro.
    - Não altera serviços críticos permanentemente.

.USO
    Execução padrão:
        .\limpeza-windows.ps1

    Execução sem reiniciar:
        .\limpeza-windows.ps1 -NoReboot

    Executar SOMENTE SFC + DISM (nenhuma limpeza):
        .\limpeza-windows.ps1 -RepararSistema

    Execução sem SFC/DISM:
        .\limpeza-windows.ps1 -NoSfc

    Execução sem limpar cache do Windows Update:
        .\limpeza-windows.ps1 -NoUpdateCache

    Execução sem esvaziar lixeira:
        .\limpeza-windows.ps1 -NoRecycleBin

    Execução desativando hibernação:
        .\limpeza-windows.ps1 -DisableHibernation

    Execução configurando arquivo de paginação para 4 GB:
        .\limpeza-windows.ps1 -SetPageFile -PageFileGB 4

    Execução ativando CompactOS:
        .\limpeza-windows.ps1 -EnableCompactOS

    Execução completa, sem reboot:
        .\limpeza-windows.ps1 -DisableHibernation -SetPageFile -PageFileGB 4 -EnableCompactOS -NoReboot

    Verificação automática de integridade do disco se houver falhas:
        .\limpeza-windows.ps1 -ChkdskAction Schedule

    Limpeza completa silenciosa (sem prompts, não destrutiva — ideal para automação):
        .\limpeza-windows.ps1 -ChkdskAction Skip -EventLogCleanup None -NoReboot

    Limpar todos os eventos do Visualizador:
        .\limpeza-windows.ps1 -EventLogCleanup All

    Limpar apenas logs com eventos de falha/erro (backup automático dos erros):
        .\limpeza-windows.ps1 -EventLogCleanup ErrorOnly

    Caso a política de execução bloqueie o script, execute antes:
        Set-ExecutionPolicy Bypass -Scope Process -Force

.NOTAS
    Recomendado executar em PowerShell como Administrador.
    Testado conceitualmente para Windows 10 Pro com PowerShell 5.1 ou superior.
#>
param (
    [switch]$Help,
    [switch]$Version,

    [switch]$NoReboot,
    [switch]$NoSfc,
    [switch]$RepararSistema,
    [switch]$NoUpdateCache,
    [switch]$NoRecycleBin,

    [switch]$DisableHibernation,
    [switch]$SetPageFile,

    [switch]$EnableCompactOS,
    [switch]$NoOptimizeVolume,

    [ValidateSet('Schedule', 'Skip')]
    [string]$ChkdskAction = 'Skip',

    [ValidateSet('All', 'ErrorOnly', 'None')]
    [string]$EventLogCleanup = 'None',

    [ValidateRange(1, 64)]
    [int]$PageFileGB = 4,

    [Alias('DiretorioSaida')]
    [string]$Path
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

chcp 65001 | Out-Null

$ToolkitRoot           = Split-Path -Parent $PSScriptRoot
$CoreModulePath        = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$MaintenanceModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1'
Import-Module $CoreModulePath        -Force -ErrorAction Stop
Import-Module $MaintenanceModulePath -Force -ErrorAction Stop

$ScriptVersion = "v1.0"
$ScriptName    = $MyInvocation.MyCommand.Name
$ReportSession = $null
$LogDir = $null
$LogFile = $null

# Quando o parâmetro NÃO foi passado explicitamente → modo interativo (Ask).
# Quando foi passado explicitamente → usa o valor (inclusive o default 'Skip'/'None').
$resolvedChkdskAction    = if ($PSBoundParameters.ContainsKey('ChkdskAction'))    { $ChkdskAction }    else { 'Ask' }
$resolvedEventLogCleanup = if ($PSBoundParameters.ContainsKey('EventLogCleanup')) { $EventLogCleanup } else { 'Ask' }

function Show-Help {
    Write-Host ""
    Write-Host "Limpeza segura e manutenção do Windows 10 Pro" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\$ScriptName [opções]"
    Write-Host ""
    Write-Host "Opções:"
    Write-Host "  -Help                 Mostra esta ajuda"
    Write-Host "  -Version              Mostra a versão"
    Write-Host "  -NoReboot             Não reinicia ao final"
    Write-Host "  -NoSfc                Não executa SFC/DISM"
    Write-Host "  -RepararSistema   Executa APENAS SFC + DISM, ignora toda a limpeza"
    Write-Host "  -NoUpdateCache        Não limpa cache do Windows Update"
    Write-Host "  -NoRecycleBin         Não esvazia a lixeira"
    Write-Host "  -DisableHibernation   Desativa hibernação"
    Write-Host "  -SetPageFile          Configura pagefile fixo"
    Write-Host "  -PageFileGB 4         Define tamanho do pagefile em GB"
    Write-Host "  -EnableCompactOS      Ativa CompactOS"
    Write-Host "  -NoOptimizeVolume     Não executa Optimize-Volume"
    Write-Host "  -ChkdskAction         Schedule | Skip  (padrão interativo; Skip para automação)"
    Write-Host "  -EventLogCleanup      All | ErrorOnly | None  (padrão interativo; None para automação)"
    Write-Host "  -PageFileGB N         Define tamanho do pagefile em GB (1-64, padrão: 4)"
    Write-Host "  -DiretorioSaida <dir> Raiz de relatorios. Padrao: configuracao global ou C:\WBA\Relatorios"
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName -NoReboot"
    Write-Host "  .\$ScriptName -RepararSistema"
    Write-Host "  .\$ScriptName -RepararSistema -NoReboot"
    Write-Host "  .\$ScriptName -NoSfc -NoReboot"
    Write-Host "  .\$ScriptName -DisableHibernation -NoReboot"
    Write-Host "  .\$ScriptName -SetPageFile -PageFileGB 4 -NoReboot"
    Write-Host "  .\$ScriptName -DisableHibernation -SetPageFile -PageFileGB 4 -EnableCompactOS -NoReboot"
    Write-Host "  .\$ScriptName -ChkdskAction Schedule"
    Write-Host "  .\$ScriptName -EventLogCleanup ErrorOnly -NoReboot"
    Write-Host "  .\$ScriptName -ChkdskAction Skip -EventLogCleanup None -NoReboot"
    Write-Host ""
    Write-Host "Caso necessário:"
    Write-Host "  Set-ExecutionPolicy Bypass -Scope Process -Force"
    Write-Host ""
}

function Write-Step {
    param (
        [string]$Message,
        [int]$Percent
    )

    Write-Progress -Activity "Limpeza e manutenção segura do Windows" -Status $Message -PercentComplete $Percent
    Write-Host ""
    Write-Host "[$Percent%] $Message" -ForegroundColor Cyan
}

if ($Help) {
    Show-Help
    exit 0
}

if ($Version) {
    Write-Host "Versão: $ScriptVersion" -ForegroundColor Green
    exit 0
}

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
$LogDir = $ReportSession.LogsPath
$LogFile = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$([System.IO.Path]::GetFileNameWithoutExtension($ScriptName)).log"

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$transcriptActive = $false
try {
    Start-Transcript -Path $LogFile -Encoding UTF8 -ErrorAction Stop
    $transcriptActive = $true
}
catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Limpeza e manutenção segura do Windows - $ScriptVersion" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Log: $LogFile" -ForegroundColor Yellow

if ($RepararSistema) {
    Write-Host ""
    Write-Host "Modo: apenas verificacao de integridade SFC + DISM (nenhuma limpeza sera executada)" -ForegroundColor Yellow
    Write-Host ""

    Write-Step "Executando verificacao de integridade SFC" 30
    Invoke-Safe "sfc /scannow" {
        sfc /scannow
    }

    Write-Step "Executando limpeza do Component Store via DISM" 60
    Invoke-ComponentStoreCleanup -Level Standard

    Write-Step "Executando restauracao de integridade via DISM" 90
    Invoke-Safe "DISM RestoreHealth" {
        dism.exe /Online /Cleanup-Image /RestoreHealth
    }

    Write-Step "Verificacao de integridade concluida" 100
    Write-Progress -Activity "Limpeza e manutenção segura do Windows" -Completed

    if ($transcriptActive) { Stop-Transcript }

    if (-not $NoReboot) {
        Write-Host ""
        Write-Host "Verificacao concluida. Reiniciando em 30 segundos..." -ForegroundColor Yellow
        shutdown /r /t 30 /c "Reinicio apos verificacao de integridade SFC/DISM."
    }
    else {
        Write-Host ""
        Write-Host "Verificacao de integridade concluida sem reinicializacao." -ForegroundColor Green
        Write-Host "Log salvo em: $LogFile" -ForegroundColor Green
    }

    exit 0
}

Write-Step "Coletando informações iniciais do disco C:" 5
$DiskBefore = Get-DiskInfo
$DiskBefore | Format-Table -AutoSize

Write-Step "Verificando eventos de falha no sistema de arquivos" 7
Invoke-FilesystemCheck -Action $resolvedChkdskAction -CallerScript $ScriptName

Write-Step "Limpando arquivos temporários do usuário atual" 10
Invoke-Safe "TEMP do usuário atual" {
    Remove-SafePath -Path "$env:TEMP"
}

Write-Step "Limpando arquivos temporários dos perfis locais" 18
Invoke-Safe "TEMP dos perfis em C:\Users" {
    Get-ChildItem "C:\Users" -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-SafePath -Path "$($_.FullName)\AppData\Local\Temp"
        }
}

Write-Step "Limpando temporários do Windows" 25
Invoke-Safe "$env:SystemRoot\Temp" {
    Remove-SafePath -Path "$env:SystemRoot\Temp"
}

Write-Step "Removendo dumps de memória e falhas" 35
Invoke-Safe "Minidumps" {
    Remove-SafePath -Path "$env:SystemRoot\Minidump"
}

Invoke-Safe "MEMORY.DMP" {
    Remove-Item "$env:SystemRoot\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
}

Invoke-Safe "Relatórios WER do sistema com mais de 7 dias" {
    Remove-SafePath -Path "C:\ProgramData\Microsoft\Windows\WER\ReportArchive" -OlderThanDays 7
    Remove-SafePath -Path "C:\ProgramData\Microsoft\Windows\WER\ReportQueue" -OlderThanDays 7
}

Invoke-Safe "Relatórios WER dos usuários com mais de 7 dias" {
    Get-ChildItem "C:\Users" -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-SafePath -Path "$($_.FullName)\AppData\Local\Microsoft\Windows\WER\ReportArchive" -OlderThanDays 7
            Remove-SafePath -Path "$($_.FullName)\AppData\Local\Microsoft\Windows\WER\ReportQueue" -OlderThanDays 7
        }
}

Write-Step "Limpando logs antigos não essenciais" 45
Invoke-Safe "Logs antigos em $env:SystemRoot\Logs com mais de 30 dias" {
    Remove-SafePath -Path "$env:SystemRoot\Logs" -OlderThanDays 30
}

Invoke-Safe "Logs antigos do DISM com mais de 15 dias" {
    Remove-SafePath -Path "$env:SystemRoot\Logs\DISM" -OlderThanDays 15
}

Invoke-Safe "Logs antigos do CBS preservando CBS.log ativo" {
    Get-ChildItem "$env:SystemRoot\Logs\CBS" -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ne "CBS.log" -and $_.LastWriteTime -lt (Get-Date).AddDays(-15)
        } |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

Write-Step "Verificando limpeza do Visualizador de Eventos" 52
Invoke-EventLogMaintenance -Action $resolvedEventLogCleanup -BackupPath $LogDir

Write-Step "Limpando cache de miniaturas e ícones dos usuários" 55
Invoke-Safe "thumbcache_*.db e iconcache_*.db" {
    Get-ChildItem "C:\Users" -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-Item "$($_.FullName)\AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
            Remove-Item "$($_.FullName)\AppData\Local\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
        }
}

if (-not $NoUpdateCache) {
    Write-Step "Limpando cache de download do Windows Update" 65

    $WuState   = (Get-Service wuauserv -ErrorAction SilentlyContinue).Status
    $BitsState = (Get-Service bits     -ErrorAction SilentlyContinue).Status

    Invoke-Safe "Parar serviços wuauserv e bits" {
        Stop-Service wuauserv,bits -Force -ErrorAction SilentlyContinue
    }

    Invoke-Safe "Limpar $env:SystemRoot\SoftwareDistribution\Download" {
        Remove-SafePath -Path "$env:SystemRoot\SoftwareDistribution\Download"
    }

    Invoke-Safe "Restaurar serviços wuauserv e bits" {
        if ($WuState   -eq 'Running') { Start-Service wuauserv -ErrorAction SilentlyContinue }
        if ($BitsState -eq 'Running') { Start-Service bits     -ErrorAction SilentlyContinue }
    }
}

if (-not $NoRecycleBin) {
    Write-Step "Esvaziando lixeira" 72
    Invoke-Safe "Clear-RecycleBin" {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }
}

Write-Step "Executando limpeza integrada do Windows" 78
Invoke-Safe "cleanmgr silencioso (sageset:99 + sagerun:99)" {
    $cleanKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    Get-ChildItem $cleanKey -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name StateFlags0099 -Type DWord -Value 2 -ErrorAction SilentlyContinue
    }
    Start-Process cleanmgr.exe -ArgumentList "/sagerun:99" -Wait -ErrorAction SilentlyContinue
}

if (-not $NoSfc) {
    Write-Step "Executando verificação de integridade SFC" 84
    Invoke-Safe "sfc /scannow" {
        sfc /scannow
    }

    Write-Step "Executando limpeza do Component Store via DISM" 88
    Invoke-ComponentStoreCleanup -Level Standard

    Write-Step "Executando restauração de integridade via DISM" 91
    Invoke-Safe "DISM RestoreHealth" {
        dism.exe /Online /Cleanup-Image /RestoreHealth
    }
}

if ($DisableHibernation) {
    Write-Step "Desabilitando hibernação" 93
    Invoke-Safe "powercfg /h off" {
        powercfg.exe /h off
    }
}

if ($SetPageFile) {
    Write-Step "Configurando arquivo de paginação para $PageFileGB GB" 95

    Invoke-Safe "Configuração do pagefile" {
        $PageFileMB = $PageFileGB * 1024

        $ComputerSystem = Get-CimInstance Win32_ComputerSystem
        $ComputerSystem | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false }

        $PageFile = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue

        if ($PageFile) {
            $PageFile | Set-CimInstance -Property @{
                InitialSize = $PageFileMB
                MaximumSize = $PageFileMB
            }
        }
        else {
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                Name        = "$env:SystemDrive\pagefile.sys"
                InitialSize = $PageFileMB
                MaximumSize = $PageFileMB
            } | Out-Null
        }
    }
}

if ($EnableCompactOS) {
    Write-Step "Ativando CompactOS" 96
    Invoke-Safe "compact /compactos:always" {
        compact.exe /compactos:always
    }
}

if (-not $NoOptimizeVolume) {
    $driveLetter = $env:SystemDrive.TrimEnd(':')
    Write-Step "Otimizando volume $env:SystemDrive" 97
    Invoke-Safe "Optimize-Volume $env:SystemDrive" {
        Optimize-Volume -DriveLetter $driveLetter -Verbose
    }
}

Write-Step "Coletando informações finais do disco C:" 99
$DiskAfter = Get-DiskInfo
$DiskAfter | Format-Table -AutoSize

try {
    $FreedGB = [math]::Round(($DiskAfter.LivreGB - $DiskBefore.LivreGB), 2)
    Write-Host ""
    Write-Host "Espaço aproximado liberado: $FreedGB GB" -ForegroundColor Green
}
catch {
    Write-Host "Não foi possível calcular o espaço liberado." -ForegroundColor Yellow
}

Write-Step "Finalizado" 100
Write-Progress -Activity "Limpeza e manutenção segura do Windows" -Completed

if ($transcriptActive) { Stop-Transcript }

if (-not $NoReboot) {
    Write-Host ""
    Write-Host "Limpeza concluída. Reiniciando em 30 segundos..." -ForegroundColor Yellow
    shutdown /r /t 30 /c "Reinício após limpeza e manutenção segura do sistema."
}
else {
    Write-Host ""
    Write-Host "Limpeza concluída sem reinicialização." -ForegroundColor Green
    Write-Host "Log salvo em: $LogFile" -ForegroundColor Green
}
