#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostico de travamentos graficos, tela preta, DWM e driver de video no Windows.

.DESCRIPTION
    Coleta evidencias tecnicas para investigacao de congelamento com tela preta, reinicializacao forcada,
    falhas do Desktop Window Manager (dwm.exe), TDR, WHEA, Kernel-Power e erros em componentes DirectX.

    O script e conservador: no modo Diagnostico nao altera configuracoes do Windows, nao remove drivers e nao
    aplica reparos. O modo Assistido amplia a coleta com DXDiag, exportacao dos logs EVTX e HTML por padrao,
    mas tambem nao aplica alteracoes permanentes.

.FUNCIONALIDADES
    - Cria uma sessao padronizada em C:\WBA\Relatorios\Diagnostics\<timestamp>.
    - Coleta GPU, driver, INF, assinatura, PnP, monitores e resolucao atual.
    - Consulta eventos recentes relacionados a Display, DWM, DirectX, WHEA, BugCheck e Kernel-Power.
    - Consulta falhas de aplicativos ligados a aceleracao grafica: dwm.exe, explorer.exe, Chrome, Edge,
      WebView2, WhatsApp, Teams, StartMenuExperienceHost e SearchApp.
    - Le chaves TDR em HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers.
    - Coleta informacoes de energia relevantes para tela preta e retorno de suspensao.
    - Opcionalmente exporta System.evtx e Application.evtx.
    - Opcionalmente executa dxdiag /t para gerar relatorio de DirectX.
    - Gera relatorio TXT, JSON e HTML opcional.

.PARAMETER Modo
    Define a profundidade da execucao: Diagnostico ou Assistido.
    Diagnostico: coleta padrao sem alterar configuracoes.
    Assistido  : coleta padrao + HTML + DXDiag + exportacao EVTX.

.PARAMETER Dias
    Quantidade de dias retroativos para consulta de eventos. Padrao: 7.

.PARAMETER MaxEventos
    Quantidade maxima de eventos lidos por log antes do filtro local. Padrao: 5000.

.PARAMETER GerarHtml
    Gera relatorio HTML alem do TXT e JSON.

.PARAMETER GerarJson
    Mantido por compatibilidade operacional. O JSON e gerado por padrao.

.PARAMETER ExportarEvtx
    Exporta os logs System.evtx e Application.evtx para a pasta logs da sessao.

.PARAMETER ColetarDxDiag
    Executa dxdiag /t e salva o resultado em logs\dxdiag.txt.

.PARAMETER AbrirRelatorio
    Abre o relatorio HTML quando -GerarHtml estiver ativo. Caso contrario, abre o TXT.

.PARAMETER Path
    Raiz de relatorios escolhida pelo usuario. Quando omitido, usa ReportsRoot persistente do toolkit ou
    C:\WBA\Relatorios.

.EXAMPLE
    .\Diagnostico-Driver-Grafico.ps1

.EXAMPLE
    .\Diagnostico-Driver-Grafico.ps1 -GerarHtml

.EXAMPLE
    .\Diagnostico-Driver-Grafico.ps1 -Modo Assistido

.EXAMPLE
    .\Diagnostico-Driver-Grafico.ps1 -Dias 14 -ExportarEvtx -ColetarDxDiag -GerarHtml

.NOTES
    Autor  : WBA Windows Toolkit
    Versao : 0.1
    Requer : PowerShell 5.1+
    Escopo : Diagnostico seguro. Nao desinstala driver, nao usa DDU e nao altera registro.

.LINK
    https://codeberg.org/wbaamaral/wba-windows-toolkit
#>

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Assistido')]
    [string]$Modo = 'Diagnostico',

    [ValidateRange(1, 90)]
    [int]$Dias = 7,

    [ValidateRange(100, 20000)]
    [int]$MaxEventos = 5000,

    [switch]$GerarHtml,

    [switch]$GerarJson,

    [switch]$ExportarEvtx,

    [switch]$ColetarDxDiag,

    [switch]$AbrirRelatorio,

    [Alias('DiretorioSaida')]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

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
$ToolkitModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $ToolkitModulePath -Force -ErrorAction Stop

$ScriptVersion = 'v0.1'
$script:GfxSession = $null

# WBA-DOCS: Category=Diagnostics; Related=Diagnostico-Reparo-HD100.ps1,Inventario-Hardware-Software.ps1; Manual=Diagnostico de driver grafico e tela preta

if ($Modo -eq 'Assistido') {
    $GerarHtml = $true
    $ExportarEvtx = $true
    $ColetarDxDiag = $true
}

function Get-GfxUtf8BomEncoding {
    [CmdletBinding()]
    param()
    return Get-Utf8BomEncoding
}

function Write-GfxTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [switch]$Append
    )
    Write-TextFileUtf8 -Path $Path -Content $Content -Append:$Append
}

function Initialize-GfxSession {
    [CmdletBinding()]
    param([string]$BasePath, [string]$ExecutionMode)

    $s = Initialize-ScriptSession -ModuleName 'Diagnostics' -BasePath $BasePath -ExecutionMode $ExecutionMode
    $s | Add-Member -MemberType NoteProperty -Name 'TextReportPath'  -Value (Join-Path $s.Path     'relatorio-driver-grafico.txt')
    $s | Add-Member -MemberType NoteProperty -Name 'HtmlReportPath'  -Value (Join-Path $s.Path     'relatorio-driver-grafico.html')
    $s | Add-Member -MemberType NoteProperty -Name 'JsonReportPath'  -Value (Join-Path $s.Path     'diagnostico-driver-grafico.json')
    $s | Add-Member -MemberType NoteProperty -Name 'TranscriptPath'  -Value (Join-Path $s.LogsPath 'driver-grafico-transcript.log')
    $s | Add-Member -MemberType NoteProperty -Name 'InternalLogPath' -Value (Join-Path $s.LogsPath 'driver-grafico.log')
    $s | Add-Member -MemberType NoteProperty -Name 'DxDiagPath'      -Value (Join-Path $s.LogsPath 'dxdiag.txt')
    return $s
}

function Write-GfxLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $logPath = if ($script:GfxSession) { $script:GfxSession.InternalLogPath } else { $null }
    Write-ScriptLog -Message $Message -Level $Level -LogPath $logPath
}

function Write-GfxSection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Section $Title
    Write-GfxLog -Message $Title
}

function ConvertFrom-GfxCimDate {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }

    try {
        return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)
    }
    catch {
        try { return [datetime]$Value } catch { return $null }
    }
}

function Format-GfxDateTime {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $date = ConvertFrom-GfxCimDate -Value $Value
    if ($null -eq $date) { return 'N/I' }
    return $date.ToString('yyyy-MM-dd HH:mm:ss')
}

function Format-GfxFileSize {
    [CmdletBinding()]
    param([AllowNull()]$Bytes)

    if ($null -eq $Bytes) { return 'N/I' }

    try {
        $value = [long]$Bytes
        if ($value -le 0) { return 'N/I' }
        return Format-FileSize -Bytes $value
    }
    catch {
        return 'N/I'
    }
}

function Limit-GfxText {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [int]$MaxLength = 500
    )

    if ($null -eq $Value) { return '' }
    $text = ([string]$Value -replace '\s+', ' ').Trim()
    if ($text.Length -gt $MaxLength) {
        return $text.Substring(0, $MaxLength) + '...'
    }

    return $text
}

function New-GfxFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Critico', 'Alto', 'Medio', 'Baixo', 'Info')]
        [string]$Severidade,

        [Parameter(Mandatory = $true)]
        [string]$Categoria,

        [Parameter(Mandatory = $true)]
        [string]$Mensagem,

        [Parameter(Mandatory = $false)]
        [string]$Acao = ''
    )

    return [pscustomobject]@{
        Severidade = $Severidade
        Categoria = $Categoria
        Mensagem = $Mensagem
        Acao = $Acao
    }
}

function Get-GfxSafeCimInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ClassName,
        [string]$Namespace = 'root/cimv2',
        [string]$Filter
    )
    return @(Get-CimInstanceSafe -ClassName $ClassName -Namespace $Namespace -Filter $Filter)
}

function Get-GfxVideoInventory {
    [CmdletBinding()]
    param()

    $items = @(Get-GfxSafeCimInstance -ClassName 'Win32_VideoController')
    $result = foreach ($gpu in $items) {
        $driverDate = ConvertFrom-GfxCimDate -Value $gpu.DriverDate
        $driverAgeDays = $null
        if ($null -ne $driverDate) {
            $driverAgeDays = [int]((Get-Date) - $driverDate).TotalDays
        }

        [pscustomobject]@{
            Name = [string]$gpu.Name
            AdapterCompatibility = [string]$gpu.AdapterCompatibility
            VideoProcessor = [string]$gpu.VideoProcessor
            AdapterRAM = Format-GfxFileSize -Bytes $gpu.AdapterRAM
            DriverVersion = [string]$gpu.DriverVersion
            DriverDate = Format-GfxDateTime -Value $gpu.DriverDate
            DriverAgeDays = $driverAgeDays
            CurrentResolution = if ($gpu.CurrentHorizontalResolution -and $gpu.CurrentVerticalResolution) {
                '{0}x{1}' -f $gpu.CurrentHorizontalResolution, $gpu.CurrentVerticalResolution
            } else { 'N/I' }
            CurrentRefreshRate = if ($gpu.CurrentRefreshRate) { "$($gpu.CurrentRefreshRate) Hz" } else { 'N/I' }
            Status = [string]$gpu.Status
            ConfigManagerErrorCode = $gpu.ConfigManagerErrorCode
            PNPDeviceID = [string]$gpu.PNPDeviceID
            Availability = $gpu.Availability
        }
    }

    return @($result)
}

function Get-GfxSignedDrivers {
    [CmdletBinding()]
    param()

    $drivers = @(Get-GfxSafeCimInstance -ClassName 'Win32_PnPSignedDriver') |
        Where-Object { $_.DeviceClass -eq 'DISPLAY' -or $_.ClassGuid -eq '{4d36e968-e325-11ce-bfc1-08002be10318}' }

    $result = foreach ($driver in $drivers) {
        [pscustomobject]@{
            DeviceName = [string]$driver.DeviceName
            Manufacturer = [string]$driver.Manufacturer
            DriverProviderName = [string]$driver.DriverProviderName
            DriverVersion = [string]$driver.DriverVersion
            DriverDate = Format-GfxDateTime -Value $driver.DriverDate
            InfName = [string]$driver.InfName
            IsSigned = [bool]$driver.IsSigned
            Signer = [string]$driver.Signer
            DeviceID = [string]$driver.DeviceID
        }
    }

    return @($result)
}

function Get-GfxPnpDevices {
    [CmdletBinding()]
    param()

    try {
        $devices = @(Get-PnpDevice -Class Display -ErrorAction Stop)
        return @($devices | Select-Object Class, FriendlyName, InstanceId, Status, Problem, Manufacturer)
    }
    catch {
        Write-GfxLog -Level 'WARN' -Message "Falha ao consultar Get-PnpDevice -Class Display. $($_.Exception.Message)"
        return @()
    }
}

function Convert-GfxMonitorName {
    [CmdletBinding()]
    param([AllowNull()]$NameArray)

    if ($null -eq $NameArray) { return 'N/I' }

    try {
        $chars = @()
        foreach ($code in $NameArray) {
            if ([int]$code -gt 0) {
                $chars += [char][int]$code
            }
        }

        $name = -join $chars
        if ([string]::IsNullOrWhiteSpace($name)) { return 'N/I' }
        return $name.Trim()
    }
    catch {
        return 'N/I'
    }
}

function Get-GfxMonitorInventory {
    [CmdletBinding()]
    param()

    $monitors = @(Get-GfxSafeCimInstance -Namespace 'root/wmi' -ClassName 'WmiMonitorID')
    $result = foreach ($monitor in $monitors) {
        [pscustomobject]@{
            Manufacturer = Convert-GfxMonitorName -NameArray $monitor.ManufacturerName
            ProductCode = Convert-GfxMonitorName -NameArray $monitor.ProductCodeID
            SerialNumber = Convert-GfxMonitorName -NameArray $monitor.SerialNumberID
            UserFriendlyName = Convert-GfxMonitorName -NameArray $monitor.UserFriendlyName
            Active = [bool]$monitor.Active
            InstanceName = [string]$monitor.InstanceName
        }
    }

    if (@($result).Count -eq 0) {
        try {
            $pnpMonitors = @(Get-PnpDevice -Class Monitor -ErrorAction Stop)
            $result = foreach ($monitor in $pnpMonitors) {
                [pscustomobject]@{
                    Manufacturer = 'N/I'
                    ProductCode = 'N/I'
                    SerialNumber = 'N/I'
                    UserFriendlyName = [string]$monitor.FriendlyName
                    Active = $monitor.Status -eq 'OK'
                    InstanceName = [string]$monitor.InstanceId
                }
            }
        }
        catch {
            Write-GfxLog -Level 'WARN' -Message "Falha ao consultar monitores PnP. $($_.Exception.Message)"
            $result = @()
        }
    }

    return @($result)
}

function Get-GfxTdrRegistry {
    [CmdletBinding()]
    param()

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    $properties = @('TdrLevel', 'TdrDelay', 'TdrDdiDelay', 'TdrDebugMode', 'TdrLimitCount', 'TdrLimitTime')
    $data = [ordered]@{
        Path = $path
        Exists = Test-Path -LiteralPath $path
        Values = @()
    }

    if (-not $data.Exists) {
        return [pscustomobject]$data
    }

    try {
        $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        $values = foreach ($name in $properties) {
            if ($item.PSObject.Properties.Name -contains $name) {
                [pscustomobject]@{ Name = $name; Value = $item.$name; Present = $true }
            }
            else {
                [pscustomobject]@{ Name = $name; Value = 'Padrao do Windows'; Present = $false }
            }
        }

        $data.Values = @($values)
    }
    catch {
        Write-GfxLog -Level 'WARN' -Message "Falha ao ler chaves TDR. $($_.Exception.Message)"
    }

    return [pscustomobject]$data
}

function Get-GfxPowerInfo {
    [CmdletBinding()]
    param()

    $hiberboot = 'N/I'
    $hiberPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    try {
        if (Test-Path -LiteralPath $hiberPath) {
            $hiberValue = (Get-ItemProperty -LiteralPath $hiberPath -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
            if ($null -ne $hiberValue) {
                $hiberboot = if ([int]$hiberValue -eq 1) { 'Ativado' } else { 'Desativado' }
            }
        }
    }
    catch { }

    $activeScheme = Invoke-ExternalCommand -FilePath 'powercfg.exe' -ArgumentList @('/getactivescheme')
    $sleepStates = Invoke-ExternalCommand -FilePath 'powercfg.exe' -ArgumentList @('/a')
    $videoSettings = Invoke-ExternalCommand -FilePath 'powercfg.exe' -ArgumentList @('/query', 'SCHEME_CURRENT', 'SUB_VIDEO')

    return [pscustomobject]@{
        FastStartup = $hiberboot
        ActiveScheme = Limit-GfxText -Value $activeScheme.Output -MaxLength 400
        SleepStates = Limit-GfxText -Value $sleepStates.Output -MaxLength 1200
        VideoSettings = Limit-GfxText -Value $videoSettings.Output -MaxLength 1500
    }
}

function Get-GfxProcessSnapshot {
    [CmdletBinding()]
    param()

    $names = @(
        'dwm', 'explorer', 'SearchApp', 'SearchHost', 'StartMenuExperienceHost', 'ShellExperienceHost',
        'TextInputHost', 'RuntimeBroker', 'chrome', 'msedge', 'msedgewebview2', 'WhatsApp', 'Teams',
        'OneDrive', 'GoogleDriveFS'
    )

    try {
        $processes = @(Get-Process -ErrorAction Stop | Where-Object { $names -contains $_.ProcessName })
        return @($processes | Sort-Object ProcessName, Id | Select-Object ProcessName, Id, CPU,
            @{Name='WorkingSet'; Expression={ Format-GfxFileSize -Bytes $_.WorkingSet64 }},
            @{Name='PrivateMemory'; Expression={ Format-GfxFileSize -Bytes $_.PrivateMemorySize64 }},
            StartTime)
    }
    catch {
        Write-GfxLog -Level 'WARN' -Message "Falha ao consultar processos relacionados a interface grafica. $($_.Exception.Message)"
        return @()
    }
}

function Get-GfxGpuCounters {
    [CmdletBinding()]
    param()

    try {
        $sample = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
        $processMap = @{}
        try {
            foreach ($proc in Get-Process -ErrorAction SilentlyContinue) {
                $processMap[[int]$proc.Id] = $proc.ProcessName
            }
        }
        catch { }

        $rows = @{}
        foreach ($counter in $sample.CounterSamples) {
            $instance = [string]$counter.InstanceName
            if ($instance -notmatch 'pid_(\d+)') { continue }

            $processId = [int]$Matches[1]
            if (-not $rows.ContainsKey($processId)) {
                $processName = if ($processMap.ContainsKey($processId)) { $processMap[$processId] } else { 'PID ' + $processId }
                $rows[$processId] = [pscustomobject]@{
                    ProcessId = $processId
                    ProcessName = $processName
                    GpuUtilization = 0.0
                }
            }

            $rows[$processId].GpuUtilization = [double]$rows[$processId].GpuUtilization + [double]$counter.CookedValue
        }

        return @($rows.Values | Sort-Object GpuUtilization -Descending | Select-Object -First 15)
    }
    catch {
        Write-GfxLog -Level 'WARN' -Message "Contadores de GPU indisponiveis neste Windows/driver. $($_.Exception.Message)"
        return @()
    }
}

function ConvertTo-GfxEventRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$WinEvent)

    return [pscustomobject]@{
        TimeCreated = $WinEvent.TimeCreated
        LogName = $WinEvent.LogName
        ProviderName = $WinEvent.ProviderName
        Id = $WinEvent.Id
        LevelDisplayName = $WinEvent.LevelDisplayName
        Message = Limit-GfxText -Value $WinEvent.Message -MaxLength 1200
    }
}

function Get-GfxRecentEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Since,

        [Parameter(Mandatory = $true)]
        [int]$MaximumEvents
    )

    $systemProviderPattern = '(?i)^(Display|nvlddmkm|amdkmdag|atikmdag|igfx|iigd_dch|Intel.*Graphics|dxgkrnl|Microsoft-Windows-DxgKrnl|Microsoft-Windows-WHEA-Logger|Microsoft-Windows-Kernel-Power|Microsoft-Windows-Kernel-Boot|Microsoft-Windows-Kernel-General|Microsoft-Windows-WER-SystemErrorReporting|BugCheck)$'
    $systemMessagePattern = '(?i)(display driver|driver de video|driver de vídeo|stopped responding|parou de responder|TDR|timeout detection|video scheduler|dxgkrnl|LiveKernelEvent|hardware error|erro de hardware|WHEA|black screen|tela preta|GPU|graphics|grafico|gráfico|nvlddmkm|amdkmdag|atikmdag|igfx|iigd_dch)'
    $applicationProviderPattern = '(?i)^(Application Error|Application Hang|Windows Error Reporting)$'
    $applicationMessagePattern = '(?i)(dwm\.exe|explorer\.exe|StartMenuExperienceHost\.exe|SearchApp\.exe|SearchHost\.exe|ShellExperienceHost\.exe|TextInputHost\.exe|RuntimeBroker\.exe|msedgewebview2\.exe|chrome\.exe|msedge\.exe|WhatsApp|Teams\.exe|d3d11\.dll|d3d12\.dll|dxgi\.dll|dxcore\.dll|KERNELBASE\.dll|ntdll\.dll|nvwgf|atio6|amdxx|igc|igd|LiveKernelEvent)'

    $systemEvents = @()
    $applicationEvents = @()

    try {
        $rawSystem = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $Since } -MaxEvents $MaximumEvents -ErrorAction Stop)
        $systemEvents = @($rawSystem | Where-Object {
            $_.ProviderName -match $systemProviderPattern -or
            $_.Message -match $systemMessagePattern -or
            $_.Id -in @(41, 1001, 4101, 6008, 17, 18, 19, 47, 55, 56)
        } | ForEach-Object { ConvertTo-GfxEventRecord -WinEvent $_ })
    }
    catch {
        Write-GfxLog -Level 'WARN' -Message "Falha ao consultar eventos do log System. $($_.Exception.Message)"
    }

    try {
        $rawApplication = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $Since } -MaxEvents $MaximumEvents -ErrorAction Stop)
        $applicationEvents = @($rawApplication | Where-Object {
            $_.ProviderName -match $applicationProviderPattern -and $_.Message -match $applicationMessagePattern
        } | ForEach-Object { ConvertTo-GfxEventRecord -WinEvent $_ })
    }
    catch {
        Write-GfxLog -Level 'WARN' -Message "Falha ao consultar eventos do log Application. $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Since = $Since
        System = @($systemEvents | Sort-Object TimeCreated -Descending)
        Application = @($applicationEvents | Sort-Object TimeCreated -Descending)
    }
}

function Get-GfxReliabilityRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][datetime]$Since)

    try {
        $records = @(Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction Stop)
        $filtered = foreach ($record in $records) {
            $time = ConvertFrom-GfxCimDate -Value $record.TimeGenerated
            if ($null -eq $time -or $time -lt $Since) { continue }

            $text = "{0} {1} {2}" -f $record.SourceName, $record.ProductName, $record.Message
            if ($text -notmatch '(?i)(Windows|Hardware|Video|Display|dwm|Desktop Window Manager|LiveKernelEvent|BlueScreen|Shut.*down|Deslig|driver|grafico|gráfico)') { continue }

            [pscustomobject]@{
                TimeGenerated = $time
                SourceName = [string]$record.SourceName
                ProductName = [string]$record.ProductName
                EventIdentifier = $record.EventIdentifier
                Message = Limit-GfxText -Value $record.Message -MaxLength 800
            }
        }

        return @($filtered | Sort-Object TimeGenerated -Descending)
    }
    catch {
        Write-GfxLog -Level 'WARN' -Message "Falha ao consultar Win32_ReliabilityRecords. $($_.Exception.Message)"
        return @()
    }
}

function Export-GfxEventLogs {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$OutputPath)

    $exports = @()
    foreach ($logName in @('System', 'Application')) {
        $target = Join-Path $OutputPath ("{0}.evtx" -f $logName)
        $result = Invoke-ExternalCommand -FilePath 'wevtutil.exe' -ArgumentList @('epl', $logName, $target)
        $exports += [pscustomobject]@{
            LogName = $logName
            Path = $target
            ExitCode = $result.ExitCode
            Output = $result.Output
            Success = ($result.ExitCode -eq 0 -and (Test-Path -LiteralPath $target))
        }
    }

    return @($exports)
}

function Invoke-GfxDxDiag {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$OutputPath)

    $result = Invoke-ExternalCommand -FilePath 'dxdiag.exe' -ArgumentList @('/t', $OutputPath)

    $waitLimit = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $waitLimit -and -not (Test-Path -LiteralPath $OutputPath)) {
        Start-Sleep -Seconds 1
    }

    return [pscustomobject]@{
        Path = $OutputPath
        ExitCode = $result.ExitCode
        Output = $result.Output
        Success = Test-Path -LiteralPath $OutputPath
    }
}

function Get-GfxFindings {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    $findings = New-Object System.Collections.ArrayList

    if (-not (Test-IsAdministrator)) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Info' -Categoria 'Execucao' -Mensagem 'O script nao esta em uma sessao elevada.' -Acao 'Se faltar informacao de eventos, execute o PowerShell como Administrador e rode novamente.'))
    }

    if ($Data.VideoControllers.Count -eq 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'GPU' -Mensagem 'Nenhuma placa de video foi retornada por Win32_VideoController.' -Acao 'Validar driver no Gerenciador de Dispositivos e reinstalar driver do fabricante.'))
    }

    foreach ($gpu in $Data.VideoControllers) {
        if ($gpu.Name -match '(?i)Microsoft Basic Display|Adaptador de Video Basico|Adaptador de Vídeo Básico') {
            [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'Driver' -Mensagem "GPU usando driver generico: $($gpu.Name)." -Acao 'Instalar driver oficial do fabricante do equipamento ou da GPU.'))
        }

        if ($gpu.ConfigManagerErrorCode -ne $null -and [int]$gpu.ConfigManagerErrorCode -ne 0) {
            [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'PnP' -Mensagem "GPU $($gpu.Name) com ConfigManagerErrorCode $($gpu.ConfigManagerErrorCode)." -Acao 'Validar estado no Gerenciador de Dispositivos e reinstalar o driver.'))
        }

        if ($gpu.DriverAgeDays -ne $null -and [int]$gpu.DriverAgeDays -gt 730) {
            [void]$findings.Add((New-GfxFinding -Severidade 'Medio' -Categoria 'Driver' -Mensagem "Driver de video possivelmente antigo: $($gpu.Name), $($gpu.DriverAgeDays) dias." -Acao 'Comparar com o driver homologado mais recente do fabricante antes de atualizar.'))
        }
    }

    foreach ($driver in $Data.SignedDrivers) {
        if ($driver.IsSigned -eq $false) {
            [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'Assinatura' -Mensagem "Driver de video nao assinado: $($driver.DeviceName) / $($driver.InfName)." -Acao 'Substituir por driver assinado e homologado.'))
        }
    }

    $displayEvents = @($Data.Events.System | Where-Object { $_.ProviderName -match '(?i)^Display$' -or $_.Id -eq 4101 -or $_.Message -match '(?i)(stopped responding|parou de responder|TDR)' })
    if ($displayEvents.Count -gt 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'TDR/Display' -Mensagem "Foram encontrados $($displayEvents.Count) eventos de Display/TDR no periodo." -Acao 'Priorizar reinstalacao limpa do driver de video e teste com aceleracao grafica desativada nos aplicativos.'))
    }

    $wheaEvents = @($Data.Events.System | Where-Object { $_.ProviderName -match '(?i)WHEA' -or $_.Message -match '(?i)(WHEA|hardware error|erro de hardware)' })
    if ($wheaEvents.Count -gt 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'Hardware/WHEA' -Mensagem "Foram encontrados $($wheaEvents.Count) eventos WHEA/erro de hardware no periodo." -Acao 'Investigar hardware, temperatura, fonte, slot, BIOS/UEFI e driver de chipset alem do driver de video.'))
    }

    $kernelPower = @($Data.Events.System | Where-Object { $_.ProviderName -match '(?i)Kernel-Power' -and $_.Id -eq 41 })
    if ($kernelPower.Count -gt 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Medio' -Categoria 'Energia' -Mensagem "Foram encontrados $($kernelPower.Count) eventos Kernel-Power 41 no periodo." -Acao 'Tratar como consequencia de travamento/reinicio forcado; correlacionar horario com DWM, Display, WHEA e BugCheck.'))
    }

    $bugCheck = @($Data.Events.System | Where-Object { $_.ProviderName -match '(?i)BugCheck|WER-SystemErrorReporting' -or $_.Id -eq 1001 })
    if ($bugCheck.Count -gt 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'BugCheck' -Mensagem "Foram encontrados $($bugCheck.Count) eventos de BugCheck/erro de sistema no periodo." -Acao 'Verificar minidumps em C:\Windows\Minidump e correlacionar com driver grafico/chipset.'))
    }

    $dwmErrors = @($Data.Events.Application | Where-Object { $_.Message -match '(?i)dwm\.exe|Desktop Window Manager' })
    if ($dwmErrors.Count -gt 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'DWM' -Mensagem "Foram encontradas $($dwmErrors.Count) falhas envolvendo dwm.exe/Desktop Window Manager." -Acao 'Priorizar driver de video, DirectX, overlays, WebView2/Chrome/Edge e aceleracao grafica.'))
    }

    $directXErrors = @($Data.Events.Application | Where-Object { $_.Message -match '(?i)d3d11\.dll|d3d12\.dll|dxgi\.dll|dxcore\.dll' })
    if ($directXErrors.Count -gt 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Medio' -Categoria 'DirectX' -Mensagem "Foram encontradas $($directXErrors.Count) falhas envolvendo DLLs DirectX." -Acao 'Testar aceleracao grafica desativada em navegadores/WebView e reinstalar driver de video.'))
    }

    $webViewErrors = @($Data.Events.Application | Where-Object { $_.Message -match '(?i)msedgewebview2\.exe|chrome\.exe|msedge\.exe|WhatsApp|Teams\.exe' })
    if ($webViewErrors.Count -gt 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Medio' -Categoria 'Apps com GPU' -Mensagem "Foram encontradas $($webViewErrors.Count) falhas em apps que usam aceleracao grafica/WebView." -Acao 'Desativar aceleracao grafica para teste e atualizar WebView2/Chrome/Edge/WhatsApp/Teams.'))
    }

    $tdrValues = @($Data.TdrRegistry.Values | Where-Object { $_.Present -eq $true })
    foreach ($value in $tdrValues) {
        if ($value.Name -eq 'TdrLevel' -and [string]$value.Value -eq '0') {
            [void]$findings.Add((New-GfxFinding -Severidade 'Alto' -Categoria 'TDR' -Mensagem 'TdrLevel esta definido como 0, desabilitando a recuperacao padrao de travamento da GPU.' -Acao 'Revisar alteracao manual da chave GraphicsDrivers e restaurar comportamento padrao do Windows.'))
        }
    }

    if ($Data.Power.FastStartup -eq 'Ativado') {
        [void]$findings.Add((New-GfxFinding -Severidade 'Baixo' -Categoria 'Energia' -Mensagem 'Inicializacao rapida do Windows esta ativada.' -Acao 'Se o problema ocorrer apos ligar o computador, testar desativacao temporaria da inicializacao rapida.'))
    }

    if ($findings.Count -eq 0) {
        [void]$findings.Add((New-GfxFinding -Severidade 'Info' -Categoria 'Resumo' -Mensagem 'Nenhum indicio forte de falha grafica foi encontrado no periodo analisado.' -Acao 'Aumentar -Dias, exportar EVTX e correlacionar com horario exato do congelamento.'))
    }

    return @($findings)
}

function Get-GfxOverallStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Findings)

    if (@($Findings | Where-Object { $_.Severidade -eq 'Critico' }).Count -gt 0) { return 'CRITICO' }
    if (@($Findings | Where-Object { $_.Severidade -eq 'Alto' }).Count -gt 0) { return 'ALTO' }
    if (@($Findings | Where-Object { $_.Severidade -eq 'Medio' }).Count -gt 0) { return 'ATENCAO' }
    return 'NORMAL'
}

function Get-GfxProbableCategory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Findings)

    $priority = @('TDR/Display', 'DWM', 'Hardware/WHEA', 'BugCheck', 'DirectX', 'Apps com GPU', 'Driver', 'PnP', 'Energia')
    foreach ($category in $priority) {
        if (@($Findings | Where-Object { $_.Categoria -eq $category -and $_.Severidade -in @('Critico', 'Alto', 'Medio') }).Count -gt 0) {
            return $category
        }
    }

    return 'Inconclusivo'
}

function New-GfxTextReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add('============================================================')
    $lines.Add(' DIAGNOSTICO DRIVER GRAFICO / TELA PRETA')
    $lines.Add('============================================================')
    $lines.Add('')
    $lines.Add(('Computador:     {0}' -f $Data.ComputerName))
    $lines.Add(('Usuario:        {0}' -f $Data.UserName))
    $lines.Add(('Windows:        {0}' -f $Data.OperatingSystem.Caption))
    $lines.Add(('Build:          {0}' -f $Data.OperatingSystem.BuildNumber))
    $lines.Add(('Execucao:       {0}' -f $Data.GeneratedAt))
    $lines.Add(('Modo:           {0}' -f $Data.Mode))
    $lines.Add(('Periodo:        Ultimos {0} dia(s), desde {1}' -f $Data.Days, $Data.Events.Since))
    $lines.Add('')
    $lines.Add('------------------------------------------------------------')
    $lines.Add(' RESUMO')
    $lines.Add('------------------------------------------------------------')
    $lines.Add(('Status geral:                    {0}' -f $Data.Summary.Status))
    $lines.Add(('Categoria provavel:              {0}' -f $Data.Summary.ProbableCategory))
    $lines.Add(('GPUs detectadas:                 {0}' -f $Data.VideoControllers.Count))
    $lines.Add(('Drivers DISPLAY assinados:       {0}' -f @($Data.SignedDrivers | Where-Object { $_.IsSigned -eq $true }).Count))
    $lines.Add(('Eventos System relevantes:       {0}' -f $Data.Events.System.Count))
    $lines.Add(('Eventos Application relevantes:  {0}' -f $Data.Events.Application.Count))
    $lines.Add(('Registros de confiabilidade:     {0}' -f $Data.ReliabilityRecords.Count))
    $lines.Add(('Inicializacao rapida:            {0}' -f $Data.Power.FastStartup))
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' ACHADOS')
    $lines.Add('------------------------------------------------------------')
    foreach ($finding in $Data.Findings) {
        $lines.Add(('[{0}] {1}: {2}' -f $finding.Severidade.ToUpper(), $finding.Categoria, $finding.Mensagem))
        if (-not [string]::IsNullOrWhiteSpace($finding.Acao)) {
            $lines.Add(('  Acao sugerida: {0}' -f $finding.Acao))
        }
    }
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' GPU / DRIVER')
    $lines.Add('------------------------------------------------------------')
    if ($Data.VideoControllers.Count -eq 0) {
        $lines.Add('Nenhuma GPU retornada por Win32_VideoController.')
    }
    foreach ($gpu in $Data.VideoControllers) {
        $lines.Add(('Nome:             {0}' -f $gpu.Name))
        $lines.Add(('Fabricante:       {0}' -f $gpu.AdapterCompatibility))
        $lines.Add(('Processador:      {0}' -f $gpu.VideoProcessor))
        $lines.Add(('VRAM:             {0}' -f $gpu.AdapterRAM))
        $lines.Add(('Driver:           {0}' -f $gpu.DriverVersion))
        $lines.Add(('Data driver:      {0}' -f $gpu.DriverDate))
        $lines.Add(('Idade driver:     {0} dias' -f $gpu.DriverAgeDays))
        $lines.Add(('Resolucao atual:  {0}' -f $gpu.CurrentResolution))
        $lines.Add(('Refresh atual:    {0}' -f $gpu.CurrentRefreshRate))
        $lines.Add(('Status:           {0}' -f $gpu.Status))
        $lines.Add(('Erro PnP:         {0}' -f $gpu.ConfigManagerErrorCode))
        $lines.Add(('PNPDeviceID:      {0}' -f $gpu.PNPDeviceID))
        $lines.Add('')
    }

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' DRIVERS DISPLAY ASSINADOS')
    $lines.Add('------------------------------------------------------------')
    if ($Data.SignedDrivers.Count -eq 0) {
        $lines.Add('Nenhum driver DISPLAY retornado por Win32_PnPSignedDriver.')
    }
    foreach ($driver in $Data.SignedDrivers) {
        $lines.Add(('{0} | {1} | {2} | INF={3} | Assinado={4}' -f $driver.DeviceName, $driver.DriverVersion, $driver.DriverDate, $driver.InfName, $driver.IsSigned))
    }
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' MONITORES')
    $lines.Add('------------------------------------------------------------')
    if ($Data.Monitors.Count -eq 0) {
        $lines.Add('Nenhum monitor retornado.')
    }
    foreach ($monitor in $Data.Monitors) {
        $lines.Add(('{0} | Fabricante={1} | Ativo={2} | Serie={3}' -f $monitor.UserFriendlyName, $monitor.Manufacturer, $monitor.Active, $monitor.SerialNumber))
    }
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' TDR / GRAPHICSDRIVERS')
    $lines.Add('------------------------------------------------------------')
    foreach ($value in $Data.TdrRegistry.Values) {
        $lines.Add(('{0}: {1}' -f $value.Name, $value.Value))
    }
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' EVENTOS SYSTEM RELEVANTES')
    $lines.Add('------------------------------------------------------------')
    if ($Data.Events.System.Count -eq 0) {
        $lines.Add('Nenhum evento relevante encontrado no log System.')
    }
    foreach ($evt in @($Data.Events.System | Select-Object -First 40)) {
        $lines.Add(('{0} | {1} | ID {2} | {3}' -f $evt.TimeCreated, $evt.ProviderName, $evt.Id, $evt.LevelDisplayName))
        $lines.Add(('  {0}' -f (Limit-GfxText -Value $evt.Message -MaxLength 350)))
    }
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' EVENTOS APPLICATION RELEVANTES')
    $lines.Add('------------------------------------------------------------')
    if ($Data.Events.Application.Count -eq 0) {
        $lines.Add('Nenhum evento relevante encontrado no log Application.')
    }
    foreach ($evt in @($Data.Events.Application | Select-Object -First 40)) {
        $lines.Add(('{0} | {1} | ID {2} | {3}' -f $evt.TimeCreated, $evt.ProviderName, $evt.Id, $evt.LevelDisplayName))
        $lines.Add(('  {0}' -f (Limit-GfxText -Value $evt.Message -MaxLength 350)))
    }
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' PROCESSOS RELACIONADOS')
    $lines.Add('------------------------------------------------------------')
    if ($Data.Processes.Count -eq 0) {
        $lines.Add('Nenhum processo alvo estava ativo no momento da coleta.')
    }
    foreach ($proc in $Data.Processes) {
        $lines.Add(('{0} PID={1} CPU={2} RAM={3} Privado={4}' -f $proc.ProcessName, $proc.Id, $proc.CPU, $proc.WorkingSet, $proc.PrivateMemory))
    }
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' RECOMENDACAO OPERACIONAL')
    $lines.Add('------------------------------------------------------------')
    $lines.Add('1. Se houver DWM/TDR/Display: reinstalar driver de video de forma limpa com driver oficial/homologado.')
    $lines.Add('2. Desativar aceleracao grafica em Chrome, Edge, WebView/WhatsApp/Teams para teste controlado.')
    $lines.Add('3. Correlacionar Kernel-Power 41 com horario exato do congelamento; tratar como consequencia, nao causa isolada.')
    $lines.Add('4. Se houver WHEA: investigar hardware, temperatura, fonte, BIOS/UEFI e chipset.')
    $lines.Add('5. Preservar EVTX e dxdiag antes de executar limpezas agressivas ou reinstalacao de driver.')
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' ARQUIVOS GERADOS')
    $lines.Add('------------------------------------------------------------')
    $lines.Add(('Relatorio TXT:   {0}' -f $Data.Output.TextReportPath))
    $lines.Add(('Diagnostico JSON: {0}' -f $Data.Output.JsonReportPath))
    if ($Data.Output.HtmlReportPath) { $lines.Add(('Relatorio HTML:  {0}' -f $Data.Output.HtmlReportPath)) }
    if ($Data.Output.DxDiagPath) { $lines.Add(('DXDiag:          {0}' -f $Data.Output.DxDiagPath)) }
    $lines.Add(('Logs:            {0}' -f $Data.Output.LogsPath))

    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-GfxHtmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Rows,

        [Parameter(Mandatory = $true)]
        [string[]]$Columns
    )

    if ($Rows.Count -eq 0) {
        return '<p class="muted">Nenhum registro encontrado.</p>'
    }

    $head = ($Columns | ForEach-Object { '<th>' + (ConvertTo-HtmlSafe $_) + '</th>' }) -join ''
    $body = foreach ($row in $Rows) {
        $cells = foreach ($column in $Columns) {
            $value = $null
            if ($row.PSObject.Properties.Name -contains $column) {
                $value = $row.$column
            }
            '<td>' + (ConvertTo-HtmlSafe $value) + '</td>'
        }
        '<tr>' + ($cells -join '') + '</tr>'
    }

    return '<table><thead><tr>' + $head + '</tr></thead><tbody>' + (($body -join [Environment]::NewLine)) + '</tbody></table>'
}

function ConvertTo-GfxHtmlReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    $findingRows = ConvertTo-GfxHtmlRows -Rows $Data.Findings -Columns @('Severidade', 'Categoria', 'Mensagem', 'Acao')
    $gpuRows = ConvertTo-GfxHtmlRows -Rows $Data.VideoControllers -Columns @('Name', 'AdapterCompatibility', 'DriverVersion', 'DriverDate', 'DriverAgeDays', 'CurrentResolution', 'Status', 'ConfigManagerErrorCode')
    $driverRows = ConvertTo-GfxHtmlRows -Rows $Data.SignedDrivers -Columns @('DeviceName', 'DriverProviderName', 'DriverVersion', 'DriverDate', 'InfName', 'IsSigned', 'Signer')
    $monitorRows = ConvertTo-GfxHtmlRows -Rows $Data.Monitors -Columns @('UserFriendlyName', 'Manufacturer', 'ProductCode', 'SerialNumber', 'Active')
    $systemRows = ConvertTo-GfxHtmlRows -Rows (@($Data.Events.System | Select-Object -First 80)) -Columns @('TimeCreated', 'ProviderName', 'Id', 'LevelDisplayName', 'Message')
    $appRows = ConvertTo-GfxHtmlRows -Rows (@($Data.Events.Application | Select-Object -First 80)) -Columns @('TimeCreated', 'ProviderName', 'Id', 'LevelDisplayName', 'Message')
    $processRows = ConvertTo-GfxHtmlRows -Rows $Data.Processes -Columns @('ProcessName', 'Id', 'CPU', 'WorkingSet', 'PrivateMemory', 'StartTime')
    $gpuCounterRows = ConvertTo-GfxHtmlRows -Rows $Data.GpuCounters -Columns @('ProcessId', 'ProcessName', 'GpuUtilization')
    $reliabilityRows = ConvertTo-GfxHtmlRows -Rows (@($Data.ReliabilityRecords | Select-Object -First 80)) -Columns @('TimeGenerated', 'SourceName', 'ProductName', 'EventIdentifier', 'Message')
    $tdrRows = ConvertTo-GfxHtmlRows -Rows $Data.TdrRegistry.Values -Columns @('Name', 'Value', 'Present')

    $statusClass = switch ($Data.Summary.Status) {
        'CRITICO' { 'danger' }
        'ALTO' { 'danger' }
        'ATENCAO' { 'warn' }
        default { 'ok' }
    }

    $html = @"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Diagnostico Driver Grafico - $($Data.ComputerName)</title>
<style>
@page { size: A4; margin: 15mm; }
* { box-sizing: border-box; }
body { font-family: Segoe UI, Arial, sans-serif; margin: 0; background: #f5f7fb; color: #1f2937; line-height: 1.45; }
.page { max-width: 1120px; margin: 24px auto; padding: 32px; background: #fff; box-shadow: 0 10px 15px rgba(0,0,0,.08); }
.toolbar { max-width: 1120px; margin: 24px auto 0; text-align: right; }
button { border: 0; border-radius: 4px; background: #2563eb; color: #fff; cursor: pointer; font: inherit; padding: 8px 14px; }
button:hover { background: #1d4ed8; }
h1 { margin-bottom: 4px; }
h2 { border-bottom: 1px solid #d1d5db; padding-bottom: 6px; margin-top: 28px; }
.card { background: #fff; border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; margin: 12px 0; break-inside: avoid; page-break-inside: avoid; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
.metric { background: #f9fafb; border-radius: 8px; padding: 12px; border: 1px solid #e5e7eb; }
.metric b { display: block; color: #4b5563; font-size: 12px; text-transform: uppercase; margin-bottom: 6px; }
.badge { display: inline-block; border-radius: 999px; padding: 4px 10px; font-weight: 600; }
.ok { background: #dcfce7; color: #166534; }
.warn { background: #fef3c7; color: #92400e; }
.danger { background: #fee2e2; color: #991b1b; }
.muted { color: #6b7280; }
table { width: 100%; border-collapse: collapse; background: #fff; font-size: 13px; }
th, td { border: 1px solid #e5e7eb; padding: 8px; vertical-align: top; }
th { background: #f3f4f6; text-align: left; }
code { background: #eef2ff; padding: 2px 4px; border-radius: 4px; }
@media print {
  body { background: #fff; color: #000; }
  .toolbar { display: none; }
  .page { max-width: none; margin: 0; padding: 0; box-shadow: none; }
  * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
}
</style>
</head>
<body>
<div class="toolbar"><button onclick="window.print()">Imprimir relatorio</button></div>
<div class="page">
<h1>Diagnostico Driver Grafico / Tela Preta</h1>
<p class="muted">Computador: <b>$(ConvertTo-HtmlSafe $Data.ComputerName)</b> | Execucao: $(ConvertTo-HtmlSafe $Data.GeneratedAt) | Periodo: ultimos $($Data.Days) dia(s)</p>
<div class="card">
  <div class="grid">
    <div class="metric"><b>Status geral</b><span class="badge $statusClass">$(ConvertTo-HtmlSafe $Data.Summary.Status)</span></div>
    <div class="metric"><b>Categoria provavel</b>$(ConvertTo-HtmlSafe $Data.Summary.ProbableCategory)</div>
    <div class="metric"><b>GPUs</b>$($Data.VideoControllers.Count)</div>
    <div class="metric"><b>Eventos System</b>$($Data.Events.System.Count)</div>
    <div class="metric"><b>Eventos Application</b>$($Data.Events.Application.Count)</div>
    <div class="metric"><b>Inicializacao rapida</b>$(ConvertTo-HtmlSafe $Data.Power.FastStartup)</div>
  </div>
</div>

<h2>Achados</h2>
<div class="card">$findingRows</div>

<h2>GPU / Driver</h2>
<div class="card">$gpuRows</div>

<h2>Drivers DISPLAY assinados</h2>
<div class="card">$driverRows</div>

<h2>Monitores</h2>
<div class="card">$monitorRows</div>

<h2>TDR / GraphicsDrivers</h2>
<div class="card">$tdrRows</div>

<h2>Eventos System relevantes</h2>
<div class="card">$systemRows</div>

<h2>Eventos Application relevantes</h2>
<div class="card">$appRows</div>

<h2>Confiabilidade do Windows</h2>
<div class="card">$reliabilityRows</div>

<h2>Processos relacionados</h2>
<div class="card">$processRows</div>

<h2>Uso de GPU por processo, quando disponivel</h2>
<div class="card">$gpuCounterRows</div>

<h2>Energia</h2>
<div class="card">
<p><b>Plano ativo:</b> $(ConvertTo-HtmlSafe $Data.Power.ActiveScheme)</p>
<p><b>Estados de suspensao:</b> $(ConvertTo-HtmlSafe $Data.Power.SleepStates)</p>
</div>

<h2>Arquivos</h2>
<div class="card">
<p><b>TXT:</b> <code>$(ConvertTo-HtmlSafe $Data.Output.TextReportPath)</code></p>
<p><b>HTML:</b> <code>$(ConvertTo-HtmlSafe $Data.Output.HtmlReportPath)</code></p>
<p><b>JSON:</b> <code>$(ConvertTo-HtmlSafe $Data.Output.JsonReportPath)</code></p>
<p><b>Logs:</b> <code>$(ConvertTo-HtmlSafe $Data.Output.LogsPath)</code></p>
</div>
</div>
</body>
</html>
"@

    return $html
}

function Show-GfxConsoleReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    Write-Title 'DIAGNOSTICO DRIVER GRAFICO / TELA PRETA'
    Write-Info "Computador: $($Data.ComputerName)"
    Write-Info "Periodo   : ultimos $($Data.Days) dia(s)"
    Write-Info "Modo      : $($Data.Mode)"

    Write-Section 'Resumo'
    switch ($Data.Summary.Status) {
        'CRITICO' { Write-Fail "Status geral: $($Data.Summary.Status)" }
        'ALTO' { Write-Fail "Status geral: $($Data.Summary.Status)" }
        'ATENCAO' { Write-Warn "Status geral: $($Data.Summary.Status)" }
        default { Write-Ok "Status geral: $($Data.Summary.Status)" }
    }
    Write-Info "Categoria provavel: $($Data.Summary.ProbableCategory)"
    Write-Info "GPUs detectadas: $($Data.VideoControllers.Count)"
    Write-Info "Eventos System relevantes: $($Data.Events.System.Count)"
    Write-Info "Eventos Application relevantes: $($Data.Events.Application.Count)"

    Write-Section 'Achados principais'
    foreach ($finding in @($Data.Findings | Select-Object -First 8)) {
        switch ($finding.Severidade) {
            'Critico' { Write-Fail "$($finding.Categoria): $($finding.Mensagem)" }
            'Alto' { Write-Fail "$($finding.Categoria): $($finding.Mensagem)" }
            'Medio' { Write-Warn "$($finding.Categoria): $($finding.Mensagem)" }
            default { Write-Info "$($finding.Categoria): $($finding.Mensagem)" }
        }
    }

    Write-Section 'Arquivos gerados'
    Write-Ok "TXT : $($Data.Output.TextReportPath)"
    Write-Ok "JSON: $($Data.Output.JsonReportPath)"
    if ($Data.Output.HtmlReportPath) { Write-Ok "HTML: $($Data.Output.HtmlReportPath)" }
    if ($Data.Output.DxDiagPath) { Write-Ok "DXDiag: $($Data.Output.DxDiagPath)" }
    Write-Info "Logs: $($Data.Output.LogsPath)"
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if (-not (Test-IsAdministrator) -and [string]::IsNullOrWhiteSpace($Path)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        }
        else {
            "-$($kv.Key)"
            "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$script:GfxSession = Initialize-GfxSession -BasePath $Path -ExecutionMode $Modo
Start-Transcript -Path $script:GfxSession.TranscriptPath -Force | Out-Null

try {
    Write-GfxSection 'Preparacao'
    Write-GfxLog -Message "Script: $ScriptName $ScriptVersion"
    Write-GfxLog -Message "Destino: $($script:GfxSession.Path)"
    Write-GfxLog -Message "Modo: $Modo"
    Write-GfxLog -Message "Janela de eventos: $Dias dia(s)"

    $since = (Get-Date).AddDays(-1 * $Dias)

    Write-GfxSection 'Coletando sistema operacional'
    $os = @(Get-GfxSafeCimInstance -ClassName 'Win32_OperatingSystem') | Select-Object -First 1
    $computerSystem = @(Get-GfxSafeCimInstance -ClassName 'Win32_ComputerSystem') | Select-Object -First 1

    Write-GfxSection 'Coletando GPU e drivers'
    $videoControllers = @(Get-GfxVideoInventory)
    $signedDrivers = @(Get-GfxSignedDrivers)
    $pnpDevices = @(Get-GfxPnpDevices)
    $monitors = @(Get-GfxMonitorInventory)

    Write-GfxSection 'Coletando energia e TDR'
    $tdrRegistry = Get-GfxTdrRegistry
    $power = Get-GfxPowerInfo

    Write-GfxSection 'Coletando processos e contadores'
    $processes = @(Get-GfxProcessSnapshot)
    $gpuCounters = @(Get-GfxGpuCounters)

    Write-GfxSection 'Coletando eventos'
    $events = Get-GfxRecentEvents -Since $since -MaximumEvents $MaxEventos
    $reliabilityRecords = @(Get-GfxReliabilityRecords -Since $since)

    $evtxExports = @()
    if ($ExportarEvtx) {
        Write-GfxSection 'Exportando EVTX'
        $evtxExports = @(Export-GfxEventLogs -OutputPath $script:GfxSession.LogsPath)
    }

    $dxDiagResult = $null
    if ($ColetarDxDiag) {
        Write-GfxSection 'Executando DXDiag'
        $dxDiagResult = Invoke-GfxDxDiag -OutputPath $script:GfxSession.DxDiagPath
    }

    $data = [pscustomobject]@{
        Tool = 'WBA Windows Toolkit'
        Script = $ScriptName
        ScriptVersion = $ScriptVersion
        GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ComputerName = $env:COMPUTERNAME
        UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Mode = $Modo
        Days = $Dias
        OperatingSystem = [pscustomobject]@{
            Caption = if ($os) { [string]$os.Caption } else { 'N/I' }
            Version = if ($os) { [string]$os.Version } else { 'N/I' }
            BuildNumber = if ($os) { [string]$os.BuildNumber } else { 'N/I' }
            InstallDate = if ($os) { Format-GfxDateTime -Value $os.InstallDate } else { 'N/I' }
            LastBootUpTime = if ($os) { Format-GfxDateTime -Value $os.LastBootUpTime } else { 'N/I' }
            Manufacturer = if ($computerSystem) { [string]$computerSystem.Manufacturer } else { 'N/I' }
            Model = if ($computerSystem) { [string]$computerSystem.Model } else { 'N/I' }
        }
        VideoControllers = @($videoControllers)
        SignedDrivers = @($signedDrivers)
        PnpDevices = @($pnpDevices)
        Monitors = @($monitors)
        TdrRegistry = $tdrRegistry
        Power = $power
        Processes = @($processes)
        GpuCounters = @($gpuCounters)
        Events = $events
        ReliabilityRecords = @($reliabilityRecords)
        EvtxExports = @($evtxExports)
        DxDiag = $dxDiagResult
        Findings = @()
        Summary = [pscustomobject]@{}
        Output = [pscustomobject]@{
            SessionPath = $script:GfxSession.Path
            LogsPath = $script:GfxSession.LogsPath
            TextReportPath = $script:GfxSession.TextReportPath
            HtmlReportPath = if ($GerarHtml) { $script:GfxSession.HtmlReportPath } else { $null }
            JsonReportPath = $script:GfxSession.JsonReportPath
            DxDiagPath = if ($dxDiagResult -and $dxDiagResult.Success) { $script:GfxSession.DxDiagPath } else { $null }
        }
    }

    $findings = @(Get-GfxFindings -Data $data)
    $status = Get-GfxOverallStatus -Findings $findings
    $category = Get-GfxProbableCategory -Findings $findings

    $data.Findings = @($findings)
    $data.Summary = [pscustomobject]@{
        Status = $status
        ProbableCategory = $category
    }

    Write-GfxSection 'Gerando relatorios'
    $textReport = New-GfxTextReport -Data $data
    Write-GfxTextFile -Path $script:GfxSession.TextReportPath -Content $textReport

    $json = $data | ConvertTo-Json -Depth 8
    Write-GfxTextFile -Path $script:GfxSession.JsonReportPath -Content $json

    if ($GerarHtml) {
        $html = ConvertTo-GfxHtmlReport -Data $data
        Write-GfxTextFile -Path $script:GfxSession.HtmlReportPath -Content $html
    }

    Show-GfxConsoleReport -Data $data

    if ($AbrirRelatorio) {
        $target = if ($GerarHtml) { $script:GfxSession.HtmlReportPath } else { $script:GfxSession.TextReportPath }
        if (Test-Path -LiteralPath $target) {
            Start-Process -FilePath $target | Out-Null
        }
    }
}
catch {
    Write-GfxLog -Level 'ERROR' -Message "Falha geral no diagnostico. $($_.Exception.Message)"
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
