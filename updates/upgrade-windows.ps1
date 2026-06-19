#requires -version 5.1

param (
    [switch]$Help,
    [switch]$Version,

    [switch]$NoWindowsUpdate,
    [switch]$NoChocolatey,
    [switch]$NoRebootWarning,
    [switch]$PauseAtEnd,

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

$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$ToolkitModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $ToolkitModulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Updates; Manual=Atualizacao do Windows e Chocolatey

<#
.SINOPSE
    Script de atualização básica e conservadora para Windows 10 Pro.

.DESCRIÇÃO
    Este script executa uma rotina simples de atualização para ambientes Windows onde
    o módulo PSWindowsUpdate e o WinGet podem não estar disponíveis, instalados ou
    funcionais.

    A rotina utiliza preferencialmente componentes já existentes no sistema:

    1. Windows Update nativo:
       - Aciona a verificação de atualizações usando UsoClient, quando disponível.
       - Executa comandos complementares de início de download/instalação quando aceitos
         pelo sistema operacional.

    2. Chocolatey:
       - Verifica se o comando choco está disponível.
       - Atualiza o próprio Chocolatey.
       - Atualiza todos os pacotes gerenciados pelo Chocolatey.

.FUNCIONALIDADES
    - Configura console e saída para UTF-8.
    - Identifica automaticamente o nome real do script chamado.
    - Exibe ajuda com exemplos usando o nome real do arquivo.
    - Solicita elevação administrativa automaticamente, quando necessário.
    - Cria log de execução na pasta padronizada de relatorios do toolkit.
    - Inicia varredura nativa do Windows Update.
    - Atualiza pacotes via Chocolatey, quando disponível.
    - Não depende do módulo PSWindowsUpdate.
    - Não depende do WinGet.
    - Não instala novos gerenciadores de pacotes.
    - Não força reinicialização automática.

.IMPACTOS ESPERADOS
    - O Windows poderá iniciar uma nova busca por atualizações.
    - Pacotes instalados via Chocolatey poderão ser atualizados.
    - Algumas atualizações podem exigir reinicialização manual.
    - O tempo de execução pode variar conforme conexão, repositórios e quantidade de pacotes.

.PRÉ-REQUISITOS
    - Executar com privilégios administrativos.
    - Possuir acesso à internet, quando necessário.
    - O serviço Windows Update deve estar minimamente funcional.
    - O Chocolatey precisa estar instalado para a etapa de atualização de pacotes.

.O QUE ESTE SCRIPT NÃO FAZ
    - Não instala Chocolatey.
    - Não instala WinGet.
    - Não instala o módulo PSWindowsUpdate.
    - Não força reinicialização.
    - Não altera políticas permanentes do sistema.
    - Não remove pacotes.
    - Não executa limpeza de disco.

.FORMA DE USO
    Caso a política de execução bloqueie o script:

        Set-ExecutionPolicy Bypass -Scope Process -Force

    Execução padrão:

        .\NOME-REAL-DO-SCRIPT.ps1

    Exibir ajuda:

        .\NOME-REAL-DO-SCRIPT.ps1 -Help

    Exibir versão:

        .\NOME-REAL-DO-SCRIPT.ps1 -Version

    Executar somente Chocolatey:

        .\NOME-REAL-DO-SCRIPT.ps1 -NoWindowsUpdate

    Executar somente Windows Update nativo:

        .\NOME-REAL-DO-SCRIPT.ps1 -NoChocolatey

    Manter janela aberta ao final:

        .\NOME-REAL-DO-SCRIPT.ps1 -PauseAtEnd

.OBSERVAÇÃO
    Para acentuação correta no Windows PowerShell 5.1, salve este arquivo como UTF-8 BOM.
#>

$ScriptVersion = "v1.0-update-basico"
$ErrorActionPreference = "Continue"

$ReportSession = $null
$LogDir = $null
$LogFile = $null

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

function Show-Help {
    Write-Host ""
    Write-Host "Atualização básica para Windows 10 Pro" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Script:" -ForegroundColor Yellow
    Write-Host "  $ScriptName"
    Write-Host ""
    Write-Host "Caminho:" -ForegroundColor Yellow
    Write-Host "  $ScriptPath"
    Write-Host ""
    Write-Host "Uso:" -ForegroundColor Yellow
    Write-Host "  .\$ScriptName [opções]"
    Write-Host ""
    Write-Host "Opções:" -ForegroundColor Yellow
    Write-Host "  -Help              Mostra esta ajuda"
    Write-Host "  -Version           Mostra a versão"
    Write-Host "  -NoWindowsUpdate   Não aciona o Windows Update nativo"
    Write-Host "  -NoChocolatey      Não atualiza pacotes via Chocolatey"
    Write-Host "  -NoRebootWarning   Não exibe aviso de reinicialização"
    Write-Host "  -PauseAtEnd        Aguarda uma tecla antes de finalizar"
    Write-Host "  -DiretorioSaida    Raiz de relatorios. Padrao: configuracao global ou C:\WBA\Relatorios"
    Write-Host ""
    Write-Host "Exemplos:" -ForegroundColor Yellow
    Write-Host "  Set-ExecutionPolicy Bypass -Scope Process -Force"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -NoWindowsUpdate"
    Write-Host "  .\$ScriptName -NoChocolatey"
    Write-Host "  .\$ScriptName -PauseAtEnd"
    Write-Host ""
    Write-Host "Observação:" -ForegroundColor Yellow
    Write-Host "  Salve este arquivo como UTF-8 BOM no Windows PowerShell 5.1."
    Write-Host ""
}

function Write-Err {
    param (
        [string]$Message
    )

    Write-Host "[ERRO] $Message" -ForegroundColor Red
}

function Invoke-NativeWindowsUpdate {
    Write-Section "Windows Update nativo"

    $UsoClient = Get-Command UsoClient.exe -ErrorAction SilentlyContinue

    if (-not $UsoClient) {
        Write-Warn "UsoClient.exe não encontrado. A varredura nativa do Windows Update não pôde ser acionada."
        return
    }

    Invoke-Safe "Iniciar varredura do Windows Update" {
        UsoClient.exe StartScan
    }

    Start-Sleep -Seconds 2

    Invoke-Safe "Solicitar início do download de atualizações" {
        UsoClient.exe StartDownload
    }

    Start-Sleep -Seconds 2

    Invoke-Safe "Solicitar início da instalação de atualizações" {
        UsoClient.exe StartInstall
    }

    Write-Warn "O UsoClient não exibe progresso detalhado no console."
    Write-Warn "Confira o andamento em: Configurações > Atualização e Segurança > Windows Update."
}

function Invoke-ChocolateyUpgrade {
    Write-Section "Chocolatey"

    $Choco = Get-Command choco.exe -ErrorAction SilentlyContinue

    if (-not $Choco) {
        Write-Warn "Chocolatey não encontrado. A etapa de atualização de pacotes foi ignorada."
        return
    }

    Invoke-Safe "Verificar versão do Chocolatey" {
        choco.exe --version
    }

    Invoke-Safe "Atualizar Chocolatey" {
        choco.exe upgrade chocolatey -y --no-progress
    }

    Invoke-Safe "Atualizar todos os pacotes do Chocolatey" {
        choco.exe upgrade all -y --no-progress
    }
}

if ($Help) {
    Show-Help
    exit 0
}

if ($Version) {
    Write-Host "Script: $ScriptName" -ForegroundColor Cyan
    Write-Host "Versão: $ScriptVersion" -ForegroundColor Green
    exit 0
}

if (-not (Test-IsAdministrator)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        }
        else {
            "-$($kv.Key)"; "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'Updates'
$LogDir = $ReportSession.LogsPath
$LogFile = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-upgrade-windows.log"

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$transcriptActive = $false
try {
    Start-Transcript -Path $LogFile -Append -ErrorAction Stop
    $transcriptActive = $true
}
catch {
    Write-Warn "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Atualização básica do Windows - $ScriptVersion" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Script: $ScriptName" -ForegroundColor Yellow
Write-Host "Caminho: $ScriptPath" -ForegroundColor Yellow
Write-Host "Diretório: $ScriptDir" -ForegroundColor Yellow
Write-Host "Log: $LogFile" -ForegroundColor Yellow

if (-not $NoWindowsUpdate) {
    Invoke-NativeWindowsUpdate
}
else {
    Write-Warn "Etapa Windows Update ignorada por parâmetro."
}

if (-not $NoChocolatey) {
    Invoke-ChocolateyUpgrade
}
else {
    Write-Warn "Etapa Chocolatey ignorada por parâmetro."
}

Write-Section "Concluído"

if (-not $NoRebootWarning) {
    Write-Warn "Pode ser necessário reiniciar a máquina para concluir atualizações pendentes."
}

Write-Info "Rotina finalizada."
Write-Info "Log salvo em: $LogFile"

if ($transcriptActive) { Stop-Transcript }

if ($PauseAtEnd) {
    Write-Host ""
    Read-Host "Pressione ENTER para finalizar"
}
