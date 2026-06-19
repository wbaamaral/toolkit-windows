#Requires -Version 5.1
<#
.SYNOPSIS
    Padroniza idioma, locale regional e fuso horario de instalacoes Windows 10/11 Pro+ para pt-BR.

.DESCRIPTION
    Configura uma instalacao existente do Windows 10/11 (Pro ou superior) para o padrao
    brasileiro (pt-BR): pacote de idioma, idioma de exibicao, locale regional, teclado ABNT2,
    localizacao geografica e fuso horario.

    As configuracoes sao aplicadas ao usuario atual, a conta do sistema e ao perfil padrao
    de novos usuarios (via intl.cpl com propagacao automatica).

    Requer acesso a internet para download do pacote de idioma quando nao instalado.
    Requer reinicializacao para aplicar completamente o idioma de exibicao.

.FUNCIONALIDADES
    - Instala pacote de idioma pt-BR (se ausente, via LanguagePackManagement ou DISM).
    - Define pt-BR como idioma de exibicao do sistema.
    - Configura locale regional pt-BR: data, hora, moeda, separadores numericos.
    - Define teclado ABNT2 como layout principal.
    - Define localizacao geografica como Brasil (GeoID 32).
    - Propaga todas as configuracoes para conta do sistema e perfil de novos usuarios.
    - Configura fuso horario (padrao UTC-4; parametrizavel para qualquer fuso do Brasil).
    - Suporte a modo silencioso para automacao via GPO, SCCM ou scripts de implantacao.
    - Salva log completo na pasta padronizada de relatorios do toolkit.

.USO
    Execucao padrao (interativa, UTC-4):
        .\Configurar-Idioma-Regional.ps1

    Modo silencioso sem reboot (automacao, GPO, SCCM):
        .\Configurar-Idioma-Regional.ps1 -Silent -NoReboot

    Fuso horario de Brasilia (UTC-3):
        .\Configurar-Idioma-Regional.ps1 -TimeZone "E. South America Standard Time"

    Fuso horario do Acre (UTC-5):
        .\Configurar-Idioma-Regional.ps1 -TimeZone "SA Pacific Standard Time"

    Listar fusos horarios do Brasil:
        .\Configurar-Idioma-Regional.ps1 -ListTimeZones

    Se a politica de execucao bloquear:
        Set-ExecutionPolicy Bypass -Scope Process -Force

.NOTAS
    Requer privilegios de Administrador.
    Testado no Windows 10 Pro (21H2+) e Windows 11 Pro/Enterprise.
    Recomenda-se reiniciar apos a execucao para aplicar o idioma de exibicao.
    Em ambientes sem internet (WSUS bloqueado), pre-instale o pacote via DISM
    com o arquivo .cab do idioma pt-BR obtido do Volume Licensing Service Center.
#>
param (
    [switch]$Help,
    [switch]$Version,
    [switch]$ListTimeZones,
    [switch]$NoReboot,
    [switch]$Silent,

    [string]$TimeZone = "SA Western Standard Time",

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

# WBA-DOCS: Category=Configuration; Manual=Configuracao de idioma e regiao do Windows

$ScriptVersion = "v1.0"
$ScriptName    = $MyInvocation.MyCommand.Name
$ReportSession = $null
$LogDir        = $null
$LogFile       = $null

# Fusos horarios brasileiros com ID Windows, offset UTC e regioes principais
$BrazilTimeZones = [ordered]@{
    "E. South America Standard Time" = [PSCustomObject]@{ UTC = "UTC-3"; Regioes = "Brasilia/DF, Sao Paulo/SP, Rio de Janeiro/RJ, Minas Gerais/MG, Goias/GO, Parana/PR, Santa Catarina/SC, Rio Grande do Sul/RS" }
    "SA Eastern Standard Time"       = [PSCustomObject]@{ UTC = "UTC-3"; Regioes = "Fortaleza/CE, Recife/PE, Belem/PA, Maceio/AL, Natal/RN, Joao Pessoa/PB, Teresina/PI, Sao Luis/MA" }
    "Tocantins Standard Time"        = [PSCustomObject]@{ UTC = "UTC-3"; Regioes = "Palmas/TO, Araguaina/TO" }
    "Bahia Standard Time"            = [PSCustomObject]@{ UTC = "UTC-3"; Regioes = "Salvador/BA e demais municipios da Bahia" }
    "SA Western Standard Time"       = [PSCustomObject]@{ UTC = "UTC-4"; Regioes = "Manaus/AM, Porto Velho/RO, Boa Vista/RR, Cuiaba/MT, Campo Grande/MS" }
    "SA Pacific Standard Time"       = [PSCustomObject]@{ UTC = "UTC-5"; Regioes = "Rio Branco/AC, Cruzeiro do Sul/AC, extremo oeste do Amazonas/AM" }
}

# ---------------------------------------------------------------------------
# Funcoes utilitarias
# ---------------------------------------------------------------------------

function Show-Help {
    Write-Host ""
    Write-Host "Configuracao de Idioma e Regiao para Windows 10/11 Pro+ (pt-BR)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "Opcoes:"
    Write-Host "  -Help                 Mostra esta ajuda"
    Write-Host "  -Version              Mostra a versao"
    Write-Host "  -ListTimeZones        Lista fusos horarios do Brasil e encerra"
    Write-Host "  -TimeZone '<id>'      ID do fuso horario Windows (padrao: SA Western Standard Time / UTC-4)"
    Write-Host "  -Silent               Modo silencioso: sem prompts de confirmacao"
    Write-Host "  -NoReboot             Nao reinicia ao final"
    Write-Host "  -DiretorioSaida <dir> Raiz de relatorios. Padrao: configuracao global ou C:\WBA\Relatorios"
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Silent -NoReboot"
    Write-Host "  .\$ScriptName -TimeZone `"E. South America Standard Time`""
    Write-Host "  .\$ScriptName -TimeZone `"SA Pacific Standard Time`" -NoReboot"
    Write-Host "  .\$ScriptName -ListTimeZones"
    Write-Host ""
    Write-Host "Modo silencioso (GPO / SCCM / automacao):"
    Write-Host "  .\$ScriptName -Silent -NoReboot"
    Write-Host "  .\$ScriptName -Silent -NoReboot -TimeZone `"E. South America Standard Time`""
    Write-Host ""
    Write-Host "Caso necessario:"
    Write-Host "  Set-ExecutionPolicy Bypass -Scope Process -Force"
    Write-Host ""
}

function Show-BrazilTimeZones {
    Write-Host ""
    Write-Host "Fusos horarios do Brasil — valores para o parametro -TimeZone" -ForegroundColor Cyan
    Write-Host ("=" * 72)
    Write-Host ("{0,-42} {1,-6}  {2}" -f "ID Windows (use exatamente este valor)", "UTC", "Capital / Regioes")
    Write-Host ("-" * 72)

    foreach ($id in $script:BrazilTimeZones.Keys) {
        $info   = $script:BrazilTimeZones[$id]
        $marker = if ($id -eq "SA Western Standard Time") { " [PADRAO]" } else { "" }
        Write-Host ("{0,-42} {1,-6}  {2}{3}" -f $id, $info.UTC, $info.Regioes, $marker)
    }

    Write-Host ""
    Write-Host "[PADRAO] = fuso utilizado quando -TimeZone nao e informado." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Exemplo:"
    Write-Host "  .\$($script:ScriptName) -TimeZone `"E. South America Standard Time`""
    Write-Host ""
}

function Test-SupportedWindows {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { return $false }
    $caption = $os.Caption
    $build   = [int]$os.BuildNumber
    $isWin10 = $caption -match 'Windows 10' -and $build -ge 19041   # 20H1+
    $isWin11 = $caption -match 'Windows 11'
    $isPro   = $caption -match 'Pro|Enterprise|Education'
    return ($isWin10 -or $isWin11) -and $isPro
}

function Write-Step {
    param([string]$Message, [int]$Percent)
    Write-Progress -Activity "Configuracao pt-BR — $script:ScriptVersion" -Status $Message -PercentComplete $Percent
    Write-Host ""
    Write-Host "[$Percent%] $Message" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Funcoes principais
# ---------------------------------------------------------------------------

function Install-PtBRLanguage {
    Write-Host "Verificando pacote de idioma pt-BR..." -ForegroundColor Yellow

    # Verifica se pt-BR ja esta na lista de idiomas do usuario
    $currentList = Get-WinUserLanguageList -ErrorAction SilentlyContinue
    if ($currentList | Where-Object { $_.LanguageTag -eq 'pt-BR' }) {
        Write-Host "Idioma pt-BR ja presente na lista de idiomas do usuario." -ForegroundColor Green
    }
    else {
        Write-Host "pt-BR nao encontrado. Instalando pacote de idioma..." -ForegroundColor Yellow

        # Tentativa 1: modulo LanguagePackManagement (Win11 / Win10 20H1+)
        $lpModule = Get-Module -Name LanguagePackManagement -ListAvailable -ErrorAction SilentlyContinue
        if ($lpModule) {
            try {
                Import-Module LanguagePackManagement -ErrorAction Stop
                Install-Language -Language pt-BR -ErrorAction Stop
                Write-Host "Pacote pt-BR instalado via Install-Language." -ForegroundColor Green
            }
            catch {
                Write-Warning "Install-Language falhou: $($_.Exception.Message). Usando Add-WindowsCapability..."
                Add-WindowsCapability -Online -Name "Language.Basic~~~pt-BR~0.0.1.0" -ErrorAction SilentlyContinue | Out-Null
            }
        }
        else {
            # Tentativa 2: Add-WindowsCapability (Windows 10)
            $cap = Get-WindowsCapability -Online -Name "Language.Basic~~~pt-BR~0.0.1.0" -ErrorAction SilentlyContinue
            if ($cap -and $cap.State -ne 'Installed') {
                try {
                    Add-WindowsCapability -Online -Name "Language.Basic~~~pt-BR~0.0.1.0" -ErrorAction Stop | Out-Null
                    Write-Host "Capacidade de idioma pt-BR instalada." -ForegroundColor Green
                }
                catch {
                    Write-Warning "Nao foi possivel instalar via Add-WindowsCapability: $($_.Exception.Message)"
                    Write-Warning "Instale o pacote manualmente ou via DISM com o .cab do idioma pt-BR."
                }
            }
            else {
                Write-Host "Capacidade de idioma pt-BR ja instalada (via WindowsCapability)." -ForegroundColor Green
            }
        }
    }
}

function Set-PtBRUserSettings {
    Write-Host "Configurando idioma e locale para o usuario atual..." -ForegroundColor Yellow

    # Lista de idiomas: pt-BR com teclado ABNT2 como principal
    try {
        $langList = New-WinUserLanguageList 'pt-BR'
        $langList[0].InputMethodTips.Clear()
        $langList[0].InputMethodTips.Add('0416:00010416')   # ABNT2
        Set-WinUserLanguageList $langList -Force -ErrorAction Stop
        Write-Host "Lista de idiomas definida: pt-BR (ABNT2)." -ForegroundColor Green
    }
    catch { Write-Warning "Set-WinUserLanguageList: $($_.Exception.Message)" }

    # Idioma de exibicao para o usuario atual
    try {
        Set-WinUILanguageOverride -Language 'pt-BR' -ErrorAction Stop
        Write-Host "Idioma de exibicao (override): pt-BR." -ForegroundColor Green
    }
    catch { Write-Warning "Set-WinUILanguageOverride: $($_.Exception.Message)" }

    # Cultura/locale do usuario (datas, moeda, numeros)
    try {
        Set-Culture -CultureInfo 'pt-BR' -ErrorAction Stop
        Write-Host "Cultura do usuario: pt-BR." -ForegroundColor Green
    }
    catch { Write-Warning "Set-Culture: $($_.Exception.Message)" }

    # Locale do sistema (afeta programas nao-Unicode)
    try {
        Set-WinSystemLocale -SystemLocale 'pt-BR' -ErrorAction Stop
        Write-Host "Locale do sistema: pt-BR." -ForegroundColor Green
    }
    catch { Write-Warning "Set-WinSystemLocale: $($_.Exception.Message)" }

    # Localizacao geografica: Brasil (GeoID 32)
    try {
        Set-WinHomeLocation -GeoId 32 -ErrorAction Stop
        Write-Host "Localizacao geografica: Brasil (GeoID 32)." -ForegroundColor Green
    }
    catch { Write-Warning "Set-WinHomeLocation: $($_.Exception.Message)" }
}

function Invoke-IntlPropagation {
    # Aplica configuracoes pt-BR para conta do sistema e perfil padrao de novos usuarios
    # usando a abordagem documentada pela Microsoft via intl.cpl com arquivo XML.
    Write-Host "Propagando configuracoes para conta do sistema e perfil padrao..." -ForegroundColor Yellow

    $xmlPath = "$env:TEMP\ptbr-intl-$(Get-Date -Format 'yyyyMMddHHmmss').xml"

    $xmlContent = @'
<gs:GlobalizationServices xmlns:gs="urn:longhornGlobalizationUnattend">
    <gs:UserList>
        <gs:User UserID="Current"
                 CopySettingsToDefaultUserAcct="true"
                 CopySettingsToSystemAcct="true"/>
    </gs:UserList>
    <gs:LocationPreferences>
        <gs:GeoID Value="32"/>
    </gs:LocationPreferences>
    <gs:MUILanguagePreferences>
        <gs:MUILanguage Value="pt-BR"/>
        <gs:MUIFallback Value="en-US"/>
    </gs:MUILanguagePreferences>
    <gs:SystemLocale Name="pt-BR"/>
    <gs:UserLocale>
        <gs:Locale Name="pt-BR" SetAsCurrent="true" ResetAllSettings="false"/>
    </gs:UserLocale>
    <gs:InputPreferences>
        <gs:InputLanguageID Action="add" ID="0416:00010416" Default="true"/>
    </gs:InputPreferences>
</gs:GlobalizationServices>
'@

    try {
        $xmlContent | Out-File -FilePath $xmlPath -Encoding UTF8 -Force

        $proc = Start-Process -FilePath "$env:SystemRoot\System32\control.exe" `
            -ArgumentList "intl.cpl,,/f:`"$xmlPath`"" `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop

        if ($proc.ExitCode -eq 0) {
            Write-Host "Propagacao via intl.cpl concluida (ExitCode 0)." -ForegroundColor Green
        }
        else {
            Write-Warning "intl.cpl retornou ExitCode $($proc.ExitCode). Verifique o log."
        }
    }
    catch {
        Write-Warning "Falha na propagacao via intl.cpl: $($_.Exception.Message)"
    }
    finally {
        Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-BrazilTimeZone {
    param([string]$Id)

    # Valida o ID antes de aplicar
    $validTz = Get-TimeZone -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -eq $Id }

    if (-not $validTz) {
        Write-Warning "Fuso horario '$Id' nao reconhecido pelo sistema. Use -ListTimeZones para ver opcoes validas."
        return
    }

    try {
        Set-TimeZone -Id $Id -ErrorAction Stop
        $tz = Get-TimeZone
        Write-Host "Fuso horario definido: $($tz.DisplayName)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Nao foi possivel definir o fuso horario: $($_.Exception.Message)"
    }
}

function Show-Summary {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Resumo das configuracoes aplicadas" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $culture  = Get-Culture -ErrorAction SilentlyContinue
    $uiLang   = Get-WinUILanguageOverride -ErrorAction SilentlyContinue
    $sysLoc   = Get-WinSystemLocale -ErrorAction SilentlyContinue
    $tz       = Get-TimeZone -ErrorAction SilentlyContinue
    $geoId    = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
    $langList = Get-WinUserLanguageList -ErrorAction SilentlyContinue

    Write-Host "Cultura do usuario    : $($culture.Name) — $($culture.DisplayName)"
    Write-Host "Idioma de exibicao    : $uiLang"
    Write-Host "Locale do sistema     : $($sysLoc.Name)"
    Write-Host "Fuso horario          : $($tz.Id) ($($tz.DisplayName))"
    Write-Host "Localizacao (GeoID)   : $geoId"
    Write-Host "Lista de idiomas      : $($langList.LanguageTag -join ', ')"
    Write-Host "Log salvo em          : $script:LogFile"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if ($Help) { Show-Help; exit 0 }

if ($Version) {
    Write-Host "Versao: $ScriptVersion" -ForegroundColor Green
    exit 0
}

if ($ListTimeZones) { Show-BrazilTimeZones; exit 0 }

# Verificar fuso informado antes de qualquer outra coisa
if (-not ($BrazilTimeZones.Keys -contains $TimeZone)) {
    $validOnSystem = Get-TimeZone -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -eq $TimeZone }
    if (-not $validOnSystem) {
        Write-Host "ERRO: Fuso horario '$TimeZone' nao reconhecido." -ForegroundColor Red
        Write-Host "Use -ListTimeZones para ver os fusos validos do Brasil." -ForegroundColor Yellow
        exit 1
    }
}

# Elevacao administrativa
if (-not (Test-IsAdministrator)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        }
        else { "-$($kv.Key)"; "$($kv.Value)" }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'Configuration'
$LogDir        = $ReportSession.LogsPath
$LogFile       = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$([System.IO.Path]::GetFileNameWithoutExtension($ScriptName)).log"

# Criar diretorio de log
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
Write-Host " Configuracao de Idioma e Regiao pt-BR — $ScriptVersion" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Log: $LogFile" -ForegroundColor Yellow

# Modo silencioso ou interativo
if (-not $Silent) {
    $tzInfo = if ($BrazilTimeZones.Contains($TimeZone)) {
        "$TimeZone ($($BrazilTimeZones[$TimeZone].UTC))"
    } else { $TimeZone }

    Write-Host ""
    Write-Host "As seguintes configuracoes serao aplicadas:" -ForegroundColor Yellow
    Write-Host "  Idioma de exibicao : pt-BR (Portugues do Brasil)"
    Write-Host "  Locale regional    : pt-BR (data, hora, moeda, teclado ABNT2)"
    Write-Host "  Localizacao        : Brasil (GeoID 32)"
    Write-Host "  Fuso horario       : $tzInfo"
    Write-Host "  Propagacao         : usuario atual + conta sistema + novos usuarios"
    Write-Host ""
    do { $confirm = Read-Host "Confirmar e aplicar? [S/N]" } while ($confirm -notmatch '^[SsNn]$')

    if ($confirm -notmatch '^[Ss]$') {
        Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Yellow
        if ($transcriptActive) { Stop-Transcript }
        exit 0
    }
}

# --- Verificar versao do Windows ---
Write-Step "Verificando compatibilidade do sistema operacional" 5

$osOk = Test-SupportedWindows
if (-not $osOk) {
    Write-Host "AVISO: Sistema operacional nao identificado como Windows 10/11 Pro ou superior." -ForegroundColor Yellow
    Write-Host "O script continuara, mas alguns comandos podem nao estar disponiveis." -ForegroundColor Yellow
}
else {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    Write-Host "Sistema: $($osInfo.Caption) (Build $($osInfo.BuildNumber))" -ForegroundColor Green
}

# --- Instalar pacote de idioma ---
Write-Step "Instalando/verificando pacote de idioma pt-BR" 20
Invoke-Safe "Instalacao do pacote de idioma pt-BR" { Install-PtBRLanguage }

# --- Configurar usuario atual ---
Write-Step "Configurando idioma e locale do usuario atual" 45
Invoke-Safe "Configuracoes de idioma e locale pt-BR" { Set-PtBRUserSettings }

# --- Propagar para sistema e novos usuarios ---
Write-Step "Propagando configuracoes para conta do sistema e perfil padrao" 65
Invoke-Safe "Propagacao via intl.cpl" { Invoke-IntlPropagation }

# --- Fuso horario ---
Write-Step "Configurando fuso horario: $TimeZone" 82
Set-BrazilTimeZone -Id $TimeZone

# --- Resumo ---
Write-Step "Verificando configuracoes aplicadas" 95
Show-Summary

Write-Step "Configuracao concluida" 100
Write-Progress -Activity "Configuracao pt-BR — $ScriptVersion" -Completed

if ($transcriptActive) { Stop-Transcript }

if (-not $NoReboot) {
    Write-Host ""
    if (-not $Silent) {
        Write-Host "Reinicializacao necessaria para aplicar o idioma de exibicao." -ForegroundColor Yellow
        do { $rb = Read-Host "Reiniciar agora? [S/N]" } while ($rb -notmatch '^[SsNn]$')
        if ($rb -match '^[Ss]$') {
            shutdown /r /t 30 /c "Reinicio apos configuracao de idioma e regiao pt-BR."
        }
        else {
            Write-Host "Reinicializacao pendente. Execute manualmente para aplicar todas as mudancas." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Modo silencioso: reiniciando em 60 segundos." -ForegroundColor Yellow
        shutdown /r /t 60 /c "Reinicio apos configuracao de idioma e regiao pt-BR."
    }
}
else {
    Write-Host ""
    Write-Host "Configuracao concluida sem reinicializacao." -ForegroundColor Green
    Write-Host "PENDENTE: reinicie o sistema para aplicar o idioma de exibicao por completo." -ForegroundColor Yellow
    Write-Host "Log salvo em: $LogFile" -ForegroundColor Green
}
