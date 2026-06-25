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

    Funcionalidades:
    - Instala pacote de idioma pt-BR (se ausente, via LanguagePackManagement ou DISM).
    - Define pt-BR como idioma de exibicao do sistema.
    - Configura locale regional pt-BR: data, hora, moeda, separadores numericos.
    - Define teclado ABNT2 como layout principal.
    - Define localizacao geografica como Brasil (GeoID 32).
    - Propaga todas as configuracoes para conta do sistema e perfil de novos usuarios.
    - Configura fuso horario (padrao UTC-4; parametrizavel para qualquer fuso do Brasil).
    - Suporte a modo silencioso para automacao via GPO, SCCM ou scripts de implantacao.
    - Salva log completo na pasta padronizada de relatorios do toolkit.

.PARAMETER Help
    Mostra a ajuda do script e encerra.

.PARAMETER Version
    Mostra a versao do script e encerra.

.PARAMETER ListTimeZones
    Lista os fusos horarios do Brasil aceitos pelo parametro -TimeZone e encerra.

.PARAMETER NoReboot
    Nao reinicia o sistema ao final da configuracao.

.PARAMETER Silent
    Modo silencioso, sem prompts de confirmacao. Util para automacao via GPO ou SCCM.

.PARAMETER TimeZone
    ID do fuso horario Windows a aplicar. Padrao: 'SA Western Standard Time' (UTC-4).

.PARAMETER Path
    Raiz de relatorios da sessao. Quando omitido, usa a configuracao persistente
    do toolkit ou C:\WBA\Relatorios.

.EXAMPLE
    .\configurar-idioma-regional.ps1
    Execucao padrao (interativa, fuso UTC-4).

.EXAMPLE
    .\configurar-idioma-regional.ps1 -Silent -NoReboot
    Modo silencioso sem reboot (automacao, GPO, SCCM).

.EXAMPLE
    .\configurar-idioma-regional.ps1 -TimeZone "E. South America Standard Time"
    Configura para o fuso horario de Brasilia (UTC-3).

.EXAMPLE
    .\configurar-idioma-regional.ps1 -TimeZone "SA Pacific Standard Time"
    Configura para o fuso horario do Acre (UTC-5).

.EXAMPLE
    .\configurar-idioma-regional.ps1 -ListTimeZones
    Lista os fusos horarios do Brasil.

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\configurar-idioma-regional.ps1
    Caso a politica de execucao bloqueie.

.NOTES
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

try { chcp 65001 | Out-Null } catch { }

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
    Write-Info "Verificando pacote de idioma pt-BR..."

    # Verifica se pt-BR ja esta na lista de idiomas do usuario
    $currentList = Get-WinUserLanguageList -ErrorAction SilentlyContinue
    if ($currentList | Where-Object { $_.LanguageTag -eq 'pt-BR' }) {
        Write-Ok "Idioma pt-BR ja presente na lista de idiomas do usuario."
    }
    else {
        Write-Info "pt-BR nao encontrado. Instalando pacote de idioma..."

        # Tentativa 1: modulo LanguagePackManagement (Win11 / Win10 20H1+)
        $lpModule = Get-Module -Name LanguagePackManagement -ListAvailable -ErrorAction SilentlyContinue
        if ($lpModule) {
            try {
                Import-Module LanguagePackManagement -ErrorAction Stop
                Install-Language -Language pt-BR -ErrorAction Stop
                Write-Ok "Pacote pt-BR instalado via Install-Language."
            }
            catch {
                Write-Warn "Install-Language falhou: $($_.Exception.Message). Usando Add-WindowsCapability..."
                Add-WindowsCapability -Online -Name "Language.Basic~~~pt-BR~0.0.1.0" -ErrorAction SilentlyContinue | Out-Null
            }
        }
        else {
            # Tentativa 2: Add-WindowsCapability (Windows 10)
            $cap = Get-WindowsCapability -Online -Name "Language.Basic~~~pt-BR~0.0.1.0" -ErrorAction SilentlyContinue
            if ($cap -and $cap.State -ne 'Installed') {
                try {
                    Add-WindowsCapability -Online -Name "Language.Basic~~~pt-BR~0.0.1.0" -ErrorAction Stop | Out-Null
                    Write-Ok "Capacidade de idioma pt-BR instalada."
                }
                catch {
                    Write-Warn "Nao foi possivel instalar via Add-WindowsCapability: $($_.Exception.Message)"
                    Write-Warn "Instale o pacote manualmente ou via DISM com o .cab do idioma pt-BR."
                }
            }
            else {
                Write-Ok "Capacidade de idioma pt-BR ja instalada (via WindowsCapability)."
            }
        }
    }
}

function Set-PtBRUserSettings {
    Write-Info "Configurando idioma e locale para o usuario atual..."

    # Lista de idiomas: pt-BR com teclado ABNT2 como principal
    try {
        $langList = New-WinUserLanguageList 'pt-BR'
        $langList[0].InputMethodTips.Clear()
        $langList[0].InputMethodTips.Add('0416:00010416')   # ABNT2
        Set-WinUserLanguageList $langList -Force -ErrorAction Stop
        Write-Ok "Lista de idiomas definida: pt-BR (ABNT2)."
    }
    catch { Write-Warn "Set-WinUserLanguageList: $($_.Exception.Message)" }

    # Idioma de exibicao para o usuario atual
    try {
        Set-WinUILanguageOverride -Language 'pt-BR' -ErrorAction Stop
        Write-Ok "Idioma de exibicao (override): pt-BR."
    }
    catch { Write-Warn "Set-WinUILanguageOverride: $($_.Exception.Message)" }

    # Cultura/locale do usuario (datas, moeda, numeros)
    try {
        Set-Culture -CultureInfo 'pt-BR' -ErrorAction Stop
        Write-Ok "Cultura do usuario: pt-BR."
    }
    catch { Write-Warn "Set-Culture: $($_.Exception.Message)" }

    # Locale do sistema (afeta programas nao-Unicode)
    try {
        Set-WinSystemLocale -SystemLocale 'pt-BR' -ErrorAction Stop
        Write-Ok "Locale do sistema: pt-BR."
    }
    catch { Write-Warn "Set-WinSystemLocale: $($_.Exception.Message)" }

    # Localizacao geografica: Brasil (GeoID 32)
    try {
        Set-WinHomeLocation -GeoId 32 -ErrorAction Stop
        Write-Ok "Localizacao geografica: Brasil (GeoID 32)."
    }
    catch { Write-Warn "Set-WinHomeLocation: $($_.Exception.Message)" }
}

function Invoke-IntlPropagation {
    # Aplica configuracoes pt-BR para conta do sistema e perfil padrao de novos usuarios
    # usando a abordagem documentada pela Microsoft via intl.cpl com arquivo XML.
    Write-Info "Propagando configuracoes para conta do sistema e perfil padrao..."

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
            Write-Ok "Propagacao via intl.cpl concluida (ExitCode 0)."
        }
        else {
            Write-Warn "intl.cpl retornou ExitCode $($proc.ExitCode). Verifique o log."
        }
    }
    catch {
        Write-Warn "Falha na propagacao via intl.cpl: $($_.Exception.Message)"
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
        Write-Warn "Fuso horario '$Id' nao reconhecido pelo sistema. Use -ListTimeZones para ver opcoes validas."
        return
    }

    try {
        Set-TimeZone -Id $Id -ErrorAction Stop
        $tz = Get-TimeZone
        Write-Ok "Fuso horario definido: $($tz.DisplayName)"
    }
    catch {
        Write-Warn "Nao foi possivel definir o fuso horario: $($_.Exception.Message)"
    }
}

function Show-Summary {
    Write-Section "Resumo das configuracoes aplicadas"

    $culture  = Get-Culture -ErrorAction SilentlyContinue
    $uiLang   = Get-WinUILanguageOverride -ErrorAction SilentlyContinue
    $sysLoc   = Get-WinSystemLocale -ErrorAction SilentlyContinue
    $tz       = Get-TimeZone -ErrorAction SilentlyContinue
    $geoId    = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
    $langList = Get-WinUserLanguageList -ErrorAction SilentlyContinue

    Write-Info "Cultura do usuario    : $($culture.Name) — $($culture.DisplayName)"
    Write-Info "Idioma de exibicao    : $uiLang"
    Write-Info "Locale do sistema     : $($sysLoc.Name)"
    Write-Info "Fuso horario          : $($tz.Id) ($($tz.DisplayName))"
    Write-Info "Localizacao (GeoID)   : $geoId"
    Write-Info "Lista de idiomas      : $($langList.LanguageTag -join ', ')"
    Write-Info "Log salvo em          : $script:LogFile"
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if ($Help) { Show-Help; exit 0 }

if ($Version) {
    Write-Ok "Versao: $ScriptVersion"
    exit 0
}

if ($ListTimeZones) { Show-BrazilTimeZones; exit 0 }

# Verificar fuso informado antes de qualquer outra coisa
if (-not ($BrazilTimeZones.Keys -contains $TimeZone)) {
    $validOnSystem = Get-TimeZone -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -eq $TimeZone }
    if (-not $validOnSystem) {
        Write-Fail "Fuso horario '$TimeZone' nao reconhecido."
        Write-Warn "Use -ListTimeZones para ver os fusos validos do Brasil."
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
    Start-Transcript -Path $LogFile -ErrorAction Stop
    $transcriptActive = $true
}
catch {
    Write-Warn "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Title "Configuracao de Idioma e Regiao pt-BR — $ScriptVersion"
Write-Info "Log: $LogFile"

# Modo silencioso ou interativo
if (-not $Silent) {
    $tzInfo = if ($BrazilTimeZones.Contains($TimeZone)) {
        "$TimeZone ($($BrazilTimeZones[$TimeZone].UTC))"
    } else { $TimeZone }

    Write-Section "Configuracoes que serao aplicadas"
    Write-Info "  Idioma de exibicao : pt-BR (Portugues do Brasil)"
    Write-Info "  Locale regional    : pt-BR (data, hora, moeda, teclado ABNT2)"
    Write-Info "  Localizacao        : Brasil (GeoID 32)"
    Write-Info "  Fuso horario       : $tzInfo"
    Write-Info "  Propagacao         : usuario atual + conta sistema + novos usuarios"
    Write-Host ""

    $confirmado = Read-YesNo -Question "Confirmar e aplicar?" -DefaultYes $false
    if (-not $confirmado) {
        Write-Info "Operacao cancelada pelo usuario."
        if ($transcriptActive) { Stop-Transcript }
        exit 0
    }
}

# --- Verificar versao do Windows ---
Write-Step "Verificando compatibilidade do sistema operacional" 5

$osOk = Test-SupportedWindows
if (-not $osOk) {
    Write-Warn "Sistema operacional nao identificado como Windows 10/11 Pro ou superior."
    Write-Warn "O script continuara, mas alguns comandos podem nao estar disponiveis."
}
else {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    Write-Ok "Sistema: $($osInfo.Caption) (Build $($osInfo.BuildNumber))"
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
        Write-Warn "Reinicializacao necessaria para aplicar o idioma de exibicao."
        $reiniciar = Read-YesNo -Question "Reiniciar agora?" -DefaultYes $false
        if ($reiniciar) {
            shutdown /r /t 30 /c "Reinicio apos configuracao de idioma e regiao pt-BR."
        }
        else {
            Write-Warn "Reinicializacao pendente. Execute manualmente para aplicar todas as mudancas."
        }
    }
    else {
        Write-Warn "Modo silencioso: reiniciando em 60 segundos."
        shutdown /r /t 60 /c "Reinicio apos configuracao de idioma e regiao pt-BR."
    }
}
else {
    Write-Host ""
    Write-Ok "Configuracao concluida sem reinicializacao."
    Write-Warn "PENDENTE: reinicie o sistema para aplicar o idioma de exibicao por completo."
    Write-Ok "Log salvo em: $LogFile"
}
