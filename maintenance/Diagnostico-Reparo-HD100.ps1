#requires -version 5.1
<#
.SYNOPSIS
    Diagnostico assistido para uso de disco em 100% no Windows.

.DESCRIPTION
    Coleta evidencias tecnicas para investigacao do sintoma conhecido como HD100 ou Disco 100%.
    A primeira versao prioriza diagnostico seguro, relatorio tecnico e registro estruturado em JSON.

    No modo Diagnostico, o script nao aplica correcoes permanentes. Comandos com potencial de reparo,
    como SFC /scannow e DISM RestoreHealth, ficam reservados ao modo Assistido.

.FUNCIONALIDADES
    - Cria uma pasta por execucao.
    - Coleta informacoes do sistema operacional e equipamento.
    - Mede uso de disco com contadores de desempenho quando disponiveis.
    - Lista processos com maior I/O acumulado.
    - Consulta saude dos discos por CIM, Get-Disk, Get-PhysicalDisk e SMART quando disponivel.
    - Consulta eventos recentes de disco e armazenamento.
    - Executa CHKDSK /scan no volume do sistema.
    - Executa DISM CheckHealth e ScanHealth no modo diagnostico.
    - Executa SFC e DISM RestoreHealth apenas no modo Assistido.
    - Gera relatorio TXT e JSON.
    - Gera relatorio HTML opcional em UTF-8.

.PARAMETER Modo
    Define o modo de execucao: Diagnostico, Assistido, Relatorio ou Rollback.

.PARAMETER DryRun
    Simula a execucao sem chamar comandos externos como CHKDSK, DISM ou SFC.

.PARAMETER GerarHtml
    Gera relatorio HTML alem do TXT e JSON.

.PARAMETER GerarJson
    Mantido por compatibilidade. O JSON e gerado por padrao.

.PARAMETER AgendarChkdsk
    No modo Assistido, permite oferecer agendamento de CHKDSK /R com confirmacao textual.

.PARAMETER CriarPontoRestauracao
    Reservado para modo Assistido. Exige confirmacao antes de criar ponto de restauracao.

.PARAMETER Path
    Raiz de relatorios escolhida pelo usuario. Quando omitido, usa ReportsRoot persistente do toolkit ou
    C:\WBA\Relatorios.

.USO
    Execucao diagnostica padrao:
        .\Diagnostico-Reparo-HD100.ps1

    Execucao diagnostica com HTML:
        .\Diagnostico-Reparo-HD100.ps1 -GerarHtml

    Modo assistido para reparos seguros:
        .\Diagnostico-Reparo-HD100.ps1 -Modo Assistido -GerarHtml

    Simulacao sem executar comandos externos:
        .\Diagnostico-Reparo-HD100.ps1 -DryRun

    Gerar relatorio a partir da execucao mais recente:
        .\Diagnostico-Reparo-HD100.ps1 -Modo Relatorio -GerarHtml

.NOTAS
    Requer PowerShell 5.1 ou superior e Administrador local.
    O problema de disco 100% deve ser tratado como sintoma, nao como causa unica.
#>
param(
    [ValidateSet('Diagnostico', 'Assistido', 'Relatorio', 'Rollback')]
    [string]$Modo = 'Diagnostico',

    [switch]$DryRun,

    [switch]$GerarHtml,

    [switch]$GerarJson,

    [switch]$AgendarChkdsk,

    [switch]$CriarPontoRestauracao,

    [Alias('DiretorioSaida')]
    [string]$Path
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
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
$ToolkitModulePath        = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$ToolkitStartupModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Startup/WbaToolkit.Startup.psd1'
Import-Module $ToolkitModulePath        -Force -ErrorAction Stop
Import-Module $ToolkitStartupModulePath -Force -ErrorAction Stop

$ScriptVersion = 'v0.1'
$script:HD100Session = $null
$script:HD100Changes = [System.Collections.ArrayList]::new()

# WBA-DOCS: Category=Maintenance; Related=limpeza-windows.ps1; Manual=Diagnostico assistido de Disco 100%

function Test-HD100Windows {
    return ($env:OS -eq 'Windows_NT')
}

function Resolve-HD100SystemDrive {
    if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) {
        return 'C:'
    }

    return $env:SystemDrive
}

function Initialize-HD100Session {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ExecutionMode
    )

    $s = Initialize-ScriptSession -ModuleName 'HD100' -BasePath $BasePath -ExecutionMode $ExecutionMode
    $s | Add-Member -MemberType NoteProperty -Name 'TextReportPath'     -Value (Join-Path $s.Path 'relatorio-hd100.txt')
    $s | Add-Member -MemberType NoteProperty -Name 'HtmlReportPath'     -Value (Join-Path $s.Path 'relatorio-hd100.html')
    $s | Add-Member -MemberType NoteProperty -Name 'DiagnosticJsonPath' -Value (Join-Path $s.Path 'diagnostico.json')
    $s | Add-Member -MemberType NoteProperty -Name 'ChangesJsonPath'    -Value (Join-Path $s.Path 'alteracoes.json')
    $s | Add-Member -MemberType NoteProperty -Name 'RollbackJsonPath'   -Value (Join-Path $s.Path 'rollback.json')
    return $s
}

function Write-HD100Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $logPath = if ($script:HD100Session) { Join-Path $script:HD100Session.LogsPath 'hd100.log' } else { $null }
    Write-ScriptLog -Message $Message -Level $Level -LogPath $logPath
}

function Write-HD100Section {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Section $Title
    Write-HD100Log -Message $Title
}

function Get-HD100Utf8BomEncoding {
    [CmdletBinding()]
    param()
    return Get-Utf8BomEncoding
}

function Write-HD100TextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [switch]$Append
    )
    Write-TextFileUtf8 -Path $Path -Content $Content -Append:$Append
}

function Get-HD100CodePageEncoding {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$CodePage)

    try {
        return [System.Text.Encoding]::GetEncoding($CodePage)
    }
    catch {
        return [System.Text.Encoding]::Default
    }
}

function Read-HD100NativeOutputFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) {
        return ''
    }

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
    }

    $oemEncoding = Get-HD100CodePageEncoding -CodePage ([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    return $oemEncoding.GetString($bytes)
}

function Invoke-HD100ExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @(),

        [Parameter(Mandatory = $true)]
        [string]$LogName,

        [switch]$Skip,

        [switch]$Append
    )

    $logPath = Join-Path $script:HD100Session.LogsPath $LogName
    $commandLine = "$FilePath $($ArgumentList -join ' ')".Trim()
    $header = "===== $commandLine - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="

    if ($DryRun -or $Skip) {
        $content = (@($header, "DRY-RUN: $commandLine") -join "`r`n") + "`r`n"
        Write-HD100TextFile -Path $logPath -Content $content -Append:$Append

        return [pscustomobject]@{
            Executed = $false
            ExitCode = $null
            LogPath = $logPath
            Output = 'Execucao simulada.'
        }
    }

    try {
        $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("wba-hd100-{0}" -f ([System.Guid]::NewGuid().ToString('N')))
        $stdoutPath = "$tempBase.out"
        $stderrPath = "$tempBase.err"

        $process = Start-Process -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = Read-HD100NativeOutputFile -Path $stdoutPath
        $stderr = Read-HD100NativeOutputFile -Path $stderrPath
        $outputText = (@($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
        $content = (@($header, $outputText) -join "`r`n").TrimEnd() + "`r`n"
        Write-HD100TextFile -Path $logPath -Content $content -Append:$Append

        return [pscustomobject]@{
            Executed = $true
            ExitCode = $process.ExitCode
            LogPath = $logPath
            Output = $outputText
        }
    }
    catch {
        $message = $_.Exception.Message
        $content = (@($header, $message) -join "`r`n") + "`r`n"
        Write-HD100TextFile -Path $logPath -Content $content -Append:$Append

        return [pscustomobject]@{
            Executed = $true
            ExitCode = -1
            LogPath = $logPath
            Output = $message
        }
    }
    finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Confirm-HD100Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Question
    )

    if ($DryRun) {
        Write-HD100Log -Message "DRY-RUN: confirmacao simulada para '$Question'."
        return $true
    }

    return (Read-YesNo -Question $Question -DefaultYes:$false)
}

function Get-HD100LastBootPerformance {
    [CmdletBinding()]
    param()

    try {
        $event = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            Id = 100
        } -MaxEvents 1 -ErrorAction Stop

        [xml]$xml = $event.ToXml()
        $data = @{}
        foreach ($item in @($xml.Event.EventData.Data)) {
            if ($item.Name) {
                $data[$item.Name] = $item.'#text'
            }
        }

        $bootDurationMs = if ($data.ContainsKey('BootDuration')) { [int64]$data['BootDuration'] } else { $null }
        return [pscustomobject]@{
            Available = $true
            EventTime = $event.TimeCreated
            BootDurationMs = $bootDurationMs
            BootDurationSeconds = if ($bootDurationMs) { [math]::Round($bootDurationMs / 1000, 2) } else { $null }
            MainPathBootTimeMs = if ($data.ContainsKey('MainPathBootTime')) { [int64]$data['MainPathBootTime'] } else { $null }
            BootPostBootTimeMs = if ($data.ContainsKey('BootPostBootTime')) { [int64]$data['BootPostBootTime'] } else { $null }
        }
    }
    catch {
        return [pscustomobject]@{
            Available = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-HD100SystemInfo {
    [CmdletBinding()]
    param()

    $operatingSystem = $null
    $computerSystem = $null
    $bios = $null
    $computerInfo = $null
    $activePowerPlan = $null
    $lastBootPerformance = Get-HD100LastBootPerformance

    try { $computerInfo = Get-ComputerInfo -ErrorAction Stop } catch { }
    try { $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }
    try { $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { }
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop } catch { }
    try {
        $activePowerPlan = (& powercfg.exe /getactivescheme 2>&1) -join ' '
    }
    catch {
        $activePowerPlan = 'Nao disponivel.'
    }

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        DomainOrWorkgroup = if ($computerSystem) { $computerSystem.Domain } else { $env:USERDOMAIN }
        WindowsProductName = if ($computerInfo) { $computerInfo.WindowsProductName } else { $operatingSystem.Caption }
        WindowsVersion = if ($computerInfo) { $computerInfo.WindowsVersion } else { $operatingSystem.Version }
        WindowsBuild = if ($computerInfo) { $computerInfo.WindowsBuildLabEx } else { $operatingSystem.BuildNumber }
        Architecture = if ($operatingSystem) { $operatingSystem.OSArchitecture } else { $env:PROCESSOR_ARCHITECTURE }
        LastBootUpTime = if ($operatingSystem) { $operatingSystem.LastBootUpTime } else { $null }
        LastBootDurationSeconds = if ($lastBootPerformance.Available) { $lastBootPerformance.BootDurationSeconds } else { $null }
        LastBootPerformance = $lastBootPerformance
        Uptime = if ($operatingSystem) { New-TimeSpan -Start $operatingSystem.LastBootUpTime -End (Get-Date) } else { $null }
        Manufacturer = if ($computerSystem) { $computerSystem.Manufacturer } else { $null }
        Model = if ($computerSystem) { $computerSystem.Model } else { $null }
        BiosSerial = if ($bios) { $bios.SerialNumber } else { $null }
        MemoryGB = if ($computerSystem) { [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2) } else { $null }
        ActivePowerPlan = $activePowerPlan
    }
}

function Get-HD100VolumeInfo {
    [CmdletBinding()]
    param()

    $volumes = @()
    try {
        $volumes = @(Get-Volume -ErrorAction Stop | ForEach-Object {
            $sizeGB = if ($_.Size) { [math]::Round($_.Size / 1GB, 2) } else { $null }
            $freeGB = if ($_.SizeRemaining) { [math]::Round($_.SizeRemaining / 1GB, 2) } else { $null }
            $freePercent = if ($_.Size) { [math]::Round(($_.SizeRemaining / $_.Size) * 100, 2) } else { $null }

            [pscustomobject]@{
                DriveLetter = $_.DriveLetter
                FileSystemLabel = $_.FileSystemLabel
                FileSystem = $_.FileSystem
                HealthStatus = $_.HealthStatus
                SizeGB = $sizeGB
                FreeGB = $freeGB
                FreePercent = $freePercent
            }
        })
    }
    catch {
        try {
            $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
                $sizeGB = if ($_.Size) { [math]::Round($_.Size / 1GB, 2) } else { $null }
                $freeGB = if ($_.FreeSpace) { [math]::Round($_.FreeSpace / 1GB, 2) } else { $null }
                $freePercent = if ($_.Size) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) } else { $null }

                [pscustomobject]@{
                    DeviceID = $_.DeviceID
                    VolumeName = $_.VolumeName
                    FileSystem = $_.FileSystem
                    SizeGB = $sizeGB
                    FreeGB = $freeGB
                    FreePercent = $freePercent
                }
            })
        }
        catch {
            $volumes = @()
        }
    }

    return @($volumes)
}

function Get-HD100DiskUsage {
    [CmdletBinding()]
    param(
        [int]$Samples = 5,
        [int]$IntervalSeconds = 2
    )

    $counterPaths = @(
        '\PhysicalDisk(_Total)\% Disk Time',
        '\PhysicalDisk(_Total)\Avg. Disk Queue Length',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
    )

    try {
        $samplesData = Get-Counter -Counter $counterPaths -SampleInterval $IntervalSeconds -MaxSamples $Samples -ErrorAction Stop
        $grouped = $samplesData.CounterSamples | Group-Object Path
        $metrics = [ordered]@{}

        foreach ($group in $grouped) {
            $name = ($group.Name -split '\\')[-1]
            $average = ($group.Group | Measure-Object -Property CookedValue -Average).Average
            $metrics[$name] = [math]::Round($average, 4)
        }

        $diskTime = if ($metrics.Contains('% Disk Time')) { [math]::Min(100, [math]::Round($metrics['% Disk Time'], 2)) } else { $null }
        $status = if ($diskTime -eq $null) {
            'Inconclusivo'
        }
        elseif ($diskTime -ge 90) {
            'Critico'
        }
        elseif ($diskTime -ge 70) {
            'Atencao'
        }
        else {
            'Normal'
        }

        return [pscustomobject]@{
            Available = $true
            Samples = $Samples
            IntervalSeconds = $IntervalSeconds
            DiskTimePercent = $diskTime
            QueueLength = if ($metrics.Contains('Avg. Disk Queue Length')) { $metrics['Avg. Disk Queue Length'] } else { $null }
            AvgReadSeconds = if ($metrics.Contains('Avg. Disk sec/Read')) { $metrics['Avg. Disk sec/Read'] } else { $null }
            AvgWriteSeconds = if ($metrics.Contains('Avg. Disk sec/Write')) { $metrics['Avg. Disk sec/Write'] } else { $null }
            Status = $status
        }
    }
    catch {
        return [pscustomobject]@{
            Available = $false
            Error = $_.Exception.Message
            Status = 'Inconclusivo'
        }
    }
}

function Get-HD100TopIOProcess {
    [CmdletBinding()]
    param([int]$Top = 10)

    try {
        return @(Get-Process -ErrorAction Stop |
            Sort-Object -Property IOReadBytes, IOWriteBytes -Descending |
            Select-Object -First $Top Name, Id,
                @{Name = 'IOReadMB'; Expression = { [math]::Round($_.IOReadBytes / 1MB, 2) } },
                @{Name = 'IOWriteMB'; Expression = { [math]::Round($_.IOWriteBytes / 1MB, 2) } },
                @{Name = 'IOTotalMB'; Expression = { [math]::Round(($_.IOReadBytes + $_.IOWriteBytes) / 1MB, 2) } },
                CPU, StartTime)
    }
    catch {
        return @([pscustomobject]@{ Error = $_.Exception.Message })
    }
}

function Get-HD100ReliabilityCounters {
    [CmdletBinding()]
    param([object[]]$PhysicalDisks)

    $items = [System.Collections.ArrayList]::new()

    foreach ($disk in @($PhysicalDisks)) {
        try {
            $counter = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop
            $null = $items.Add([pscustomobject]@{
                FriendlyName = $disk.FriendlyName
                Wear = $counter.Wear
                Temperature = $counter.Temperature
                ReadErrorsTotal = $counter.ReadErrorsTotal
                WriteErrorsTotal = $counter.WriteErrorsTotal
                ReadErrorsCorrected = $counter.ReadErrorsCorrected
                WriteErrorsCorrected = $counter.WriteErrorsCorrected
                PowerOnHours = $counter.PowerOnHours
            })
        }
        catch { }
    }

    return @($items)
}

function Get-HD100DiskHealthScore {
    [CmdletBinding()]
    param(
        [object[]]$PhysicalDisks,
        [object[]]$Disks,
        [object[]]$DiskDrives,
        [object[]]$Smart,
        [object[]]$Reliability,
        [object[]]$Alerts
    )

    $score = 100
    $notes = [System.Collections.ArrayList]::new()

    foreach ($item in @($Smart | Where-Object { $_.PredictFailure -eq $true })) {
        $score = [math]::Min($score, 20)
        $null = $notes.Add("SMART indicou previsao de falha para $($item.InstanceName).")
    }

    foreach ($disk in @($PhysicalDisks | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' })) {
        $score -= 35
        $null = $notes.Add("Get-PhysicalDisk reportou HealthStatus $($disk.HealthStatus) em $($disk.FriendlyName).")
    }

    foreach ($disk in @($Disks | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' })) {
        $score -= 35
        $null = $notes.Add("Get-Disk reportou HealthStatus $($disk.HealthStatus) no disco $($disk.Number).")
    }

    foreach ($drive in @($DiskDrives | Where-Object { $_.Status -and $_.Status -ne 'OK' })) {
        $score -= 25
        $null = $notes.Add("Win32_DiskDrive reportou Status $($drive.Status) em $($drive.Model).")
    }

    foreach ($counter in @($Reliability)) {
        if ($null -ne $counter.Wear -and $counter.Wear -ge 0 -and $counter.Wear -le 100) {
            $lifeByWear = [math]::Max(0, 100 - [int]$counter.Wear)
            $score = [math]::Min($score, $lifeByWear)
            $null = $notes.Add("Contador de desgaste reportou $($counter.Wear)% usado em $($counter.FriendlyName).")
        }

        if ($null -ne $counter.Temperature -and $counter.Temperature -ge 60) {
            $score -= 20
            $null = $notes.Add("Temperatura elevada em $($counter.FriendlyName): $($counter.Temperature) graus C.")
        }
        elseif ($null -ne $counter.Temperature -and $counter.Temperature -ge 50) {
            $score -= 10
            $null = $notes.Add("Temperatura em atencao em $($counter.FriendlyName): $($counter.Temperature) graus C.")
        }

        $readErrors = if ($null -ne $counter.ReadErrorsTotal) { [int64]$counter.ReadErrorsTotal } else { 0 }
        $writeErrors = if ($null -ne $counter.WriteErrorsTotal) { [int64]$counter.WriteErrorsTotal } else { 0 }
        if (($readErrors + $writeErrors) -gt 0) {
            $score -= 20
            $null = $notes.Add("Contadores de confiabilidade indicam erros de leitura/escrita em $($counter.FriendlyName).")
        }
    }

    if (@($Alerts).Count -gt 0) {
        $score -= [math]::Min(30, @($Alerts).Count * 10)
    }

    $score = [math]::Max(0, [math]::Min(100, [int]$score))
    $status = if ($score -ge 85) {
        'Saudavel'
    }
    elseif ($score -ge 65) {
        'Atencao'
    }
    elseif ($score -ge 40) {
        'Degradado'
    }
    else {
        'Critico'
    }

    if (@($Reliability).Count -eq 0) {
        $null = $notes.Add('Contadores de confiabilidade nao foram expostos pelo Windows para este disco/controlador.')
    }

    return [pscustomobject]@{
        ApproximateLifePercent = $score
        Status = $status
        Gauge = New-HD100GaugeText -Percent $score
        Notes = @($notes)
    }
}

function New-HD100GaugeText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$Percent)

    $value = [math]::Max(0, [math]::Min(100, $Percent))
    $filled = [math]::Round($value / 10)
    $empty = 10 - $filled
    return '[{0}{1}] {2}%' -f ('#' * $filled), ('-' * $empty), $value
}

function Get-HD100RelevantDiskHealth {
    [CmdletBinding()]
    param(
        [object[]]$PhysicalDisks,
        [object[]]$DiskDrives,
        [object[]]$Smart,
        [object[]]$Reliability
    )

    $items = [System.Collections.ArrayList]::new()

    foreach ($disk in @($PhysicalDisks)) {
        $counter = @($Reliability | Where-Object { $_.FriendlyName -eq $disk.FriendlyName } | Select-Object -First 1)
        $null = $items.Add([pscustomobject]@{
            Nome = $disk.FriendlyName
            Tipo = $disk.MediaType
            Barramento = $disk.BusType
            TamanhoGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { $null }
            Saude = $disk.HealthStatus
            Operacional = (@($disk.OperationalStatus) -join ', ')
            DesgastePercentual = if ($counter) { $counter.Wear } else { $null }
            TemperaturaC = if ($counter) { $counter.Temperature } else { $null }
            ErrosLeitura = if ($counter) { $counter.ReadErrorsTotal } else { $null }
            ErrosEscrita = if ($counter) { $counter.WriteErrorsTotal } else { $null }
            Fonte = 'Get-PhysicalDisk'
        })
    }

    if (@($items).Count -eq 0) {
        foreach ($drive in @($DiskDrives)) {
            $smartMatch = @($Smart | Where-Object { $_.InstanceName -match [regex]::Escape(($drive.Model -replace '\s+', ' ').Trim()) } | Select-Object -First 1)
            $null = $items.Add([pscustomobject]@{
                Nome = $drive.Model
                Tipo = $drive.MediaType
                Barramento = $drive.InterfaceType
                TamanhoGB = if ($drive.Size) { [math]::Round($drive.Size / 1GB, 2) } else { $null }
                Saude = $drive.Status
                Operacional = $drive.Status
                DesgastePercentual = $null
                TemperaturaC = $null
                ErrosLeitura = $null
                ErrosEscrita = $null
                PredictFailure = if ($smartMatch) { $smartMatch.PredictFailure } else { $null }
                Fonte = 'Win32_DiskDrive'
            })
        }
    }

    return @($items)
}

function Get-HD100DiskHealth {
    [CmdletBinding()]
    param()

    $physicalDisks = @()
    $disks = @()
    $diskDrives = @()
    $smart = @()
    $reliability = @()

    try { $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size) } catch { }
    try { $disks = @(Get-Disk -ErrorAction Stop | Select-Object Number, FriendlyName, BusType, HealthStatus, OperationalStatus, PartitionStyle, Size) } catch { }
    try { $diskDrives = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Select-Object Model, InterfaceType, MediaType, Status, Size, SerialNumber) } catch { }
    try { $smart = @(Get-CimInstance -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop | Select-Object InstanceName, PredictFailure, Reason) } catch { }
    $reliability = Get-HD100ReliabilityCounters -PhysicalDisks $physicalDisks

    $alerts = [System.Collections.ArrayList]::new()
    foreach ($disk in $physicalDisks) {
        if ($disk.HealthStatus -and $disk.HealthStatus -ne 'Healthy') {
            $null = $alerts.Add("Get-PhysicalDisk indica HealthStatus '$($disk.HealthStatus)' para '$($disk.FriendlyName)'.")
        }
    }
    foreach ($disk in $disks) {
        if ($disk.HealthStatus -and $disk.HealthStatus -ne 'Healthy') {
            $null = $alerts.Add("Get-Disk indica HealthStatus '$($disk.HealthStatus)' para '$($disk.FriendlyName)'.")
        }
    }
    foreach ($drive in $diskDrives) {
        if ($drive.Status -and $drive.Status -ne 'OK') {
            $null = $alerts.Add("Win32_DiskDrive indica Status '$($drive.Status)' para '$($drive.Model)'.")
        }
    }
    foreach ($item in $smart) {
        if ($item.PredictFailure -eq $true) {
            $null = $alerts.Add("SMART PredictFailure=True para '$($item.InstanceName)'.")
        }
    }

    $summary = Get-HD100DiskHealthScore -PhysicalDisks $physicalDisks -Disks $disks -DiskDrives $diskDrives -Smart $smart -Reliability $reliability -Alerts $alerts
    $relevantDisks = Get-HD100RelevantDiskHealth -PhysicalDisks $physicalDisks -DiskDrives $diskDrives -Smart $smart -Reliability $reliability

    [pscustomobject]@{
        PhysicalDisks = @($physicalDisks)
        Disks = @($disks)
        DiskDrives = @($diskDrives)
        Smart = @($smart)
        Reliability = @($reliability)
        RelevantDisks = @($relevantDisks)
        Summary = $summary
        Alerts = @($alerts)
        Status = if (@($alerts).Count -gt 0) { 'Critico' } else { 'Normal' }
    }
}

function Get-HD100DiskEvents {
    [CmdletBinding()]
    param([int]$Days = 7)

    $sources = @(
        'Disk',
        'Ntfs',
        'storahci',
        'iaStorA',
        'iaStorAV',
        'iaStorAVC',
        'volmgr',
        'partmgr',
        'stornvme',
        'Microsoft-Windows-Kernel-Power',
        'Microsoft-Windows-DiskDiagnostic'
    )

    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            StartTime = (Get-Date).AddDays(-1 * $Days)
        } -ErrorAction Stop | Where-Object { $_.ProviderName -in $sources } | Select-Object -First 200 TimeCreated, Id, LevelDisplayName, ProviderName, Message

        $critical = @($events | Where-Object { $_.LevelDisplayName -in @('Critical', 'Error', 'Crítico', 'Erro') })
        return [pscustomobject]@{
            Available = $true
            Days = $Days
            Events = @($events)
            CriticalCount = @($critical).Count
            Status = if (@($critical).Count -gt 0) { 'Atencao' } else { 'Normal' }
        }
    }
    catch {
        return [pscustomobject]@{
            Available = $false
            Days = $Days
            Events = @()
            CriticalCount = 0
            Status = 'Inconclusivo'
            Error = $_.Exception.Message
        }
    }
}

function Invoke-HD100ChkdskScan {
    [CmdletBinding()]
    param()

    $drive = Resolve-HD100SystemDrive
    return Invoke-HD100ExternalCommand -FilePath 'chkdsk.exe' -ArgumentList @($drive, '/scan') -LogName 'chkdsk-scan.log'
}

function Register-HD100ChkdskRepair {
    [CmdletBinding()]
    param()

    Write-Warn 'O CHKDSK /R pode exigir reinicializacao e pode demorar varias horas.'
    Write-Warn 'Em discos com defeito, o processo pode ficar parado em uma porcentagem por bastante tempo.'
    Write-Warn 'Faca backup antes de continuar.'
    $confirmation = Read-Host 'Para agendar, DIGITE: AGENDAR CHKDSK'

    if ($confirmation -ne 'AGENDAR CHKDSK') {
        Write-HD100Log -Level WARN -Message 'Agendamento de CHKDSK /R cancelado pelo operador.'
        return [pscustomobject]@{ Scheduled = $false; Reason = 'Confirmacao nao fornecida.' }
    }

    $drive = Resolve-HD100SystemDrive
    $result = Invoke-HD100ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', "echo Y | chkdsk $drive /r") -LogName 'chkdsk-repair.log'
    $null = $script:HD100Changes.Add([pscustomobject]@{
        DataHora = Get-Date
        Acao = 'AgendarChkdskR'
        Alvo = $drive
        EstadoAnterior = 'Nao agendado pelo script'
        EstadoNovo = 'Agendado'
        Reversivel = $false
    })

    return [pscustomobject]@{ Scheduled = $true; Command = "chkdsk $drive /r"; Result = $result }
}

function Invoke-HD100Sfc {
    [CmdletBinding()]
    param()

    $result = Invoke-HD100ExternalCommand -FilePath 'sfc.exe' -ArgumentList @('/scannow') -LogName 'sfc.log'
    $classification = 'SFC nao conseguiu executar.'
    if ($result.Output -match 'Windows Resource Protection did not find|A Protecao de Recursos do Windows nao encontrou') {
        $classification = 'Sem violacao de integridade.'
    }
    elseif ($result.Output -match 'successfully repaired|reparou os arquivos corrompidos') {
        $classification = 'Arquivos corrompidos reparados.'
    }
    elseif ($result.Output -match 'unable to fix|nao conseguiu corrigir') {
        $classification = 'Arquivos corrompidos nao reparados.'
    }

    return [pscustomobject]@{
        Classification = $classification
        Result = $result
    }
}

function Invoke-HD100Dism {
    [CmdletBinding()]
    param([switch]$RestoreHealth)

    $logName = if ($RestoreHealth) { 'dism-restorehealth.log' } else { 'dism.log' }
    $commands = if ($RestoreHealth) {
        @(
            @('/Online', '/Cleanup-Image', '/RestoreHealth')
        )
    }
    else {
        @(
            @('/Online', '/Cleanup-Image', '/CheckHealth'),
            @('/Online', '/Cleanup-Image', '/ScanHealth')
        )
    }

    $results = foreach ($arguments in $commands) {
        Invoke-HD100ExternalCommand -FilePath 'dism.exe' -ArgumentList $arguments -LogName $logName -Append
    }

    return @($results)
}

function Get-HD100ServiceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ServiceName = @('WSearch', 'SysMain', 'DPS', 'BITS', 'Ndu', 'WinDefend', 'DiagTrack', 'OneSyncSvc')
    )

    return @(Get-ServiceStartupState -ServiceName $ServiceName)
}

function Get-HD100ScheduledTasks {
    [CmdletBinding()]
    param()

    $taskPaths = @(
        '\Microsoft\Windows\Defrag\',
        '\Microsoft\Windows\Application Experience\',
        '\Microsoft\Windows\Autochk\',
        '\Microsoft\Windows\Customer Experience Improvement Program\',
        '\Microsoft\Windows\DiskDiagnostic\'
    )

    try {
        return @(Get-ScheduledTask -ErrorAction Stop |
            Where-Object { $_.TaskPath -in $taskPaths } |
            Select-Object TaskName, TaskPath, State)
    }
    catch {
        return @([pscustomobject]@{ Error = $_.Exception.Message })
    }
}

function Get-HD100StartupItems {
    [CmdletBinding()]
    param()

    return @(Get-StartupItem)
}

function Add-HD100StartupChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)]$Item,
        [string]$PreviousState,
        [string]$NewState,
        [bool]$Reversible
    )

    $null = $script:HD100Changes.Add([pscustomobject]@{
        DataHora = Get-Date
        Acao = $Action
        Alvo = $Item.Name
        Tipo = $Item.SourceType
        Local = $Item.Location
        EstadoAnterior = $PreviousState
        EstadoNovo = $NewState
        Reversivel = $Reversible
    })
}

function Disable-HD100StartupItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Item
    )

    $results = @(Disable-StartupItem -Item $Item -DryRun:$DryRun)
    foreach ($r in @($results | Where-Object { $_.Success -and $_.Message -ne 'DryRun.' })) {
        $original = @($Item) | Where-Object { $_.Name -eq $r.Name } | Select-Object -First 1
        if ($original) {
            Add-HD100StartupChange -Action 'DesabilitarInicializacao' -Item $original -PreviousState 'On' -NewState 'Off' -Reversible $true
        }
    }
    return @($results)
}

function Enable-HD100StartupItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Item
    )

    $results = @(Enable-StartupItem -Item $Item -DryRun:$DryRun)
    foreach ($r in @($results | Where-Object { $_.Success -and $_.Message -ne 'DryRun.' })) {
        $original = @($Item) | Where-Object { $_.Name -eq $r.Name } | Select-Object -First 1
        if ($original) {
            Add-HD100StartupChange -Action 'HabilitarInicializacao' -Item $original -PreviousState 'Off' -NewState 'On' -Reversible $true
        }
    }
    return @($results)
}

function Remove-HD100StartupItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Item
    )

    $results = @(Remove-StartupItem -Item $Item -DryRun:$DryRun)
    foreach ($r in @($results | Where-Object { $_.Success -and $_.Message -ne 'DryRun.' })) {
        $original = @($Item) | Where-Object { $_.Name -eq $r.Name } | Select-Object -First 1
        if ($original) {
            Add-HD100StartupChange -Action 'RemoverInicializacao' -Item $original -PreviousState $original.State -NewState 'Removido' -Reversible $false
        }
    }
    return @($results)
}

function Show-HD100StartupItems {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Items)

    Show-StartupItem -Items $Items
}

function Invoke-HD100StartupInteractive {
    [CmdletBinding()]
    param([object[]]$Items)

    while ($true) {
        $currentItems = @(Get-HD100StartupItems)
        if (@($currentItems).Count -eq 0) {
            Write-Info 'Nenhuma entrada de inicializacao foi encontrada.'
            return
        }

        Show-HD100StartupItems -Items $currentItems
        $choice = Read-Host 'Digite o numero da entrada para alterar ou 0 para continuar'
        if ($choice -in @('', '0')) {
            return
        }

        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt @($currentItems).Count) {
            Write-Warn 'Opcao invalida.'
            continue
        }

        $item = $currentItems[$number - 1]
        Write-Host ''
        Write-Host "Selecionado: $($item.Name)" -ForegroundColor Cyan
        Write-Host "Comando: $($item.Command)"
        Write-Host '[D] Desabilitar para diagnostico'
        Write-Host '[H] Habilitar novamente'
        Write-Host '[R] Remover definitivamente da inicializacao'
        Write-Host '[V] Voltar'
        $action = (Read-Host 'Acao').Trim().ToUpperInvariant()

        switch ($action) {
            'D' { $null = Disable-HD100StartupItem -Item $item }
            'H' { $null = Enable-HD100StartupItem -Item $item }
            'R' { $null = Remove-HD100StartupItem -Item $item }
            default { }
        }
    }
}

function Get-HD100BankPlugins {
    [CmdletBinding()]
    param()

    $patterns = @('Warsaw', 'Topaz', 'GBPlugin', 'GAS Tecnologia', 'core.exe', 'Diebold', 'Guardiao', 'Guardião')
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.Name
        $patterns | Where-Object { $name -match [regex]::Escape($_) }
    } | Select-Object Name, Id, Path)

    $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $text = "$($_.Name) $($_.DisplayName) $($_.PathName)"
        $patterns | Where-Object { $text -match [regex]::Escape($_) }
    } | Select-Object Name, DisplayName, State, StartMode, PathName)

    return [pscustomobject]@{
        Processes = @($processes)
        Services = @($services)
        Detected = (@($processes).Count + @($services).Count) -gt 0
    }
}

function Get-HD100Antivirus {
    [CmdletBinding()]
    param()

    try {
        return @(Get-CimInstance -Namespace root\SecurityCenter2 -Class AntiVirusProduct -ErrorAction Stop |
            Select-Object displayName, productState, pathToSignedProductExe, timestamp)
    }
    catch {
        return @([pscustomobject]@{ Error = $_.Exception.Message })
    }
}

function Get-HD100OneDrive {
    [CmdletBinding()]
    param()

    $processes = @(Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Select-Object Name, Id, Path,
        @{Name = 'IOTotalMB'; Expression = { [math]::Round(($_.IOReadBytes + $_.IOWriteBytes) / 1MB, 2) } })

    $startupPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )

    $startup = foreach ($path in $startupPaths) {
        try {
            $item = Get-ItemProperty -Path $path -ErrorAction Stop
            if ($item.OneDrive) {
                [pscustomobject]@{ Path = $path; Command = $item.OneDrive }
            }
        }
        catch { }
    }

    return [pscustomobject]@{
        Processes = @($processes)
        Startup = @($startup)
        Detected = (@($processes).Count + @($startup).Count) -gt 0
    }
}

function Get-HD100Browsers {
    [CmdletBinding()]
    param()

    $browserProcesses = @('chrome', 'msedge', 'opera', 'firefox', 'brave')
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $browserProcesses } |
        Select-Object Name, Id, Path,
            @{Name = 'IOTotalMB'; Expression = { [math]::Round(($_.IOReadBytes + $_.IOWriteBytes) / 1MB, 2) } })

    return [pscustomobject]@{
        Processes = @($processes)
        Detected = @($processes).Count -gt 0
    }
}

function Get-HD100AdobeReader {
    [CmdletBinding()]
    param()

    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'AcroRd|Acrobat' } | Select-Object Name, Id, Path)
    return [pscustomobject]@{
        Processes = @($processes)
        Detected = @($processes).Count -gt 0
    }
}

function Get-HD100StorageDrivers {
    [CmdletBinding()]
    param()

    try {
        return @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object { $_.DeviceClass -in @('SCSIAdapter', 'HDC', 'DiskDrive', 'IDE') -or $_.DeviceName -match 'storage|ahci|nvme|intel|disk' } |
            Select-Object DeviceName, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName)
    }
    catch {
        return @([pscustomobject]@{ Error = $_.Exception.Message })
    }
}

function Get-HD100Recommendation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Diagnostic)

    $recommendations = [System.Collections.ArrayList]::new()
    $category = 'Causa nao identificada.'

    if (@($Diagnostic.DiskHealth.Alerts).Count -gt 0) {
        $category = 'Provavel falha fisica ou logica de disco.'
        $null = $recommendations.Add('Priorize backup imediato antes de qualquer reparo.')
        $null = $recommendations.Add('Evite otimizacoes agressivas ate validar a saude do disco.')
    }

    if ($Diagnostic.DiskUsage.Status -in @('Atencao', 'Critico')) {
        $null = $recommendations.Add('Verificar processos com maior I/O e correlacionar com o horario do sintoma.')
    }

    if ($Diagnostic.Events.CriticalCount -gt 0) {
        if ($category -eq 'Causa nao identificada.') {
            $category = 'Provavel falha fisica ou logica de disco.'
        }
        $null = $recommendations.Add('Analisar eventos criticos de Disk/Ntfs/storahci antes de aplicar correcoes.')
    }

    $systemDrive = Resolve-HD100SystemDrive
    $systemVolume = @($Diagnostic.Volumes | Where-Object {
        $_.DriveLetter -eq $systemDrive.TrimEnd(':') -or $_.DeviceID -eq $systemDrive
    } | Select-Object -First 1)
    if ($systemVolume -and $systemVolume.FreePercent -ne $null -and $systemVolume.FreePercent -lt 15) {
        $null = $recommendations.Add("Liberar espaco no volume $systemDrive. Livre atual: $($systemVolume.FreePercent)%.")
    }

    $services = @($Diagnostic.Services | Where-Object { $_.Name -in @('WSearch', 'SysMain') -and $_.Status -eq 'Running' })
    if (@($services).Count -gt 0) {
        if ($category -eq 'Causa nao identificada.') {
            $category = 'Provavel servico causando I/O elevado.'
        }
        $null = $recommendations.Add('No modo Assistido, testar parada temporaria de WSearch/SysMain e medir melhora.')
    }

    if ($Diagnostic.BankPlugins.Detected) {
        if ($category -eq 'Causa nao identificada.') {
            $category = 'Provavel aplicativo de terceiro.'
        }
        $null = $recommendations.Add('Plugin bancario detectado. Fazer teste controlado antes de desinstalacao manual.')
    }

    $enabledStartup = @($Diagnostic.StartupItems | Where-Object { $_.Enabled -eq $true })
    if (@($enabledStartup).Count -ge 8) {
        if ($category -eq 'Causa nao identificada.') {
            $category = 'Provavel carga excessiva na inicializacao.'
        }
        $null = $recommendations.Add("Foram encontradas $(@($enabledStartup).Count) entradas ativas na inicializacao. No modo Assistido, desabilite uma por vez para diagnostico e reinicie para medir impacto.")
    }

    if (@($recommendations).Count -eq 0) {
        $null = $recommendations.Add('Executar nova medicao durante o periodo em que o disco estiver em 100%.')
        $null = $recommendations.Add('Verificar Windows Update, indexacao e antivirus em execucao.')
    }

    return [pscustomobject]@{
        Category = $category
        Items = @($recommendations)
    }
}

function Invoke-HD100Diagnostic {
    [CmdletBinding()]
    param()

    Write-HD100Section 'Coletando informacoes do sistema'
    $system = Get-HD100SystemInfo

    Write-HD100Section 'Coletando volumes e espaco livre'
    $volumes = Get-HD100VolumeInfo

    Write-HD100Section 'Medindo uso de disco'
    $usage = Get-HD100DiskUsage

    Write-HD100Section 'Listando processos com maior I/O'
    $topIO = Get-HD100TopIOProcess

    Write-HD100Section 'Verificando saude dos discos'
    $diskHealth = Get-HD100DiskHealth

    Write-HD100Section 'Consultando eventos recentes de disco'
    $events = Get-HD100DiskEvents
    try {
        $events.Events | Format-List | Out-File -LiteralPath (Join-Path $script:HD100Session.LogsPath 'eventos-disco.log') -Encoding UTF8
    }
    catch { }

    Write-HD100Section 'Executando CHKDSK /scan'
    $chkdskScan = Invoke-HD100ChkdskScan

    Write-HD100Section 'Executando DISM CheckHealth e ScanHealth'
    $dism = Invoke-HD100Dism

    $sfc = $null
    $dismRestore = $null
    $chkdskRepair = $null

    if ($Modo -eq 'Assistido') {
        if (Confirm-HD100Action -Question 'Executar SFC /scannow agora?') {
            Write-HD100Section 'Modo Assistido: executando SFC'
            $sfc = Invoke-HD100Sfc
        }
        else {
            Write-HD100Log -Message 'SFC ignorado por decisao do operador.'
        }

        if (Confirm-HD100Action -Question 'Executar DISM RestoreHealth agora?') {
            Write-HD100Section 'Modo Assistido: executando DISM RestoreHealth'
            $dismRestore = Invoke-HD100Dism -RestoreHealth
        }
        else {
            Write-HD100Log -Message 'DISM RestoreHealth ignorado por decisao do operador.'
        }

        if ($AgendarChkdsk) {
            Write-HD100Section 'Modo Assistido: avaliando agendamento de CHKDSK /R'
            $chkdskRepair = Register-HD100ChkdskRepair
        }
    }

    Write-HD100Section 'Coletando servicos, tarefas e aplicativos relacionados'
    $services = Get-HD100ServiceState
    $tasks = Get-HD100ScheduledTasks
    $startupItems = Get-HD100StartupItems

    if ($Modo -eq 'Assistido') {
        Write-HD100Section 'Modo Assistido: avaliando programas na inicializacao'
        Invoke-HD100StartupInteractive -Items $startupItems
        $startupItems = Get-HD100StartupItems
    }

    $bankPlugins = Get-HD100BankPlugins
    $antivirus = Get-HD100Antivirus
    $oneDrive = Get-HD100OneDrive
    $browsers = Get-HD100Browsers
    $adobeReader = Get-HD100AdobeReader
    $storageDrivers = Get-HD100StorageDrivers

    $diagnostic = [pscustomobject]@{
        Metadata = [pscustomobject]@{
            Tool = 'WBA Windows Toolkit - Diagnostico HD100'
            Version = $ScriptVersion
            StartedAt = $script:HD100Session.StartedAt
            FinishedAt = Get-Date
            Mode = $Modo
            DryRun = [bool]$DryRun
            ComputerName = $env:COMPUTERNAME
        }
        System = $system
        Volumes = @($volumes)
        DiskUsage = $usage
        TopIOProcesses = @($topIO)
        DiskHealth = $diskHealth
        Events = $events
        ChkdskScan = $chkdskScan
        Dism = @($dism)
        Sfc = $sfc
        DismRestoreHealth = $dismRestore
        ChkdskRepair = $chkdskRepair
        Services = @($services)
        ScheduledTasks = @($tasks)
        StartupItems = @($startupItems)
        BankPlugins = $bankPlugins
        Antivirus = @($antivirus)
        OneDrive = $oneDrive
        Browsers = $browsers
        AdobeReader = $adobeReader
        StorageDrivers = @($storageDrivers)
    }

    $recommendation = Get-HD100Recommendation -Diagnostic $diagnostic
    $diagnostic | Add-Member -MemberType NoteProperty -Name Recommendation -Value $recommendation

    return $diagnostic
}

function Export-HD100Json {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Diagnostic)

    $Diagnostic | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:HD100Session.DiagnosticJsonPath
    @($script:HD100Changes) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:HD100Session.ChangesJsonPath
    @($script:HD100Changes | Where-Object { $_.Reversivel }) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:HD100Session.RollbackJsonPath
}

function Export-HD100ReportText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Diagnostic)

    $topProcess = @($Diagnostic.TopIOProcesses | Sort-Object IOTotalMB -Descending | Select-Object -First 1)
    $systemDrive = Resolve-HD100SystemDrive
    $systemVolume = @($Diagnostic.Volumes | Where-Object {
        $_.DriveLetter -eq $systemDrive.TrimEnd(':') -or $_.DeviceID -eq $systemDrive
    } | Select-Object -First 1)
    $diskAlert = @($Diagnostic.DiskHealth.Alerts).Count -gt 0
    $services = @($Diagnostic.Services | Where-Object { $_.Name -in @('WSearch', 'SysMain') -and $_.Status -eq 'Running' }).Name -join ', '
    if ([string]::IsNullOrWhiteSpace($services)) { $services = 'Nenhum destaque inicial' }
    $startupItems = @($Diagnostic.StartupItems)
    $startupOnCount = @($startupItems | Where-Object { $_.Enabled -eq $true }).Count
    $startupOffCount = @($startupItems | Where-Object { $_.Enabled -eq $false }).Count
    $startupRows = @($startupItems | Select-Object -First 25 | ForEach-Object {
        "[{0}] {1} | {2} | {3}`r`n  {4}" -f $_.State.ToUpperInvariant(), $_.SourceType, $_.Scope, $_.Name, $_.Command
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($startupRows)) {
        $startupRows = 'Nenhuma entrada de inicializacao encontrada nas fontes consultadas.'
    }
    $bootDuration = if ($Diagnostic.System.LastBootDurationSeconds) { "$($Diagnostic.System.LastBootDurationSeconds) segundos" } else { 'Nao disponivel' }
    $lastBoot = if ($Diagnostic.System.LastBootUpTime) { ([datetime]$Diagnostic.System.LastBootUpTime).ToString('yyyy-MM-dd HH:mm:ss') } else { 'Nao disponivel' }
    $healthSummary = $Diagnostic.DiskHealth.Summary
    $healthGauge = if ($healthSummary) { $healthSummary.Gauge } else { '[----------] Inconclusivo' }
    $healthStatus = if ($healthSummary) { $healthSummary.Status } else { $Diagnostic.DiskHealth.Status }
    $healthNotes = @($Diagnostic.DiskHealth.Summary.Notes | Select-Object -First 6)
    if (@($healthNotes).Count -eq 0) {
        $healthNotes = @('Nenhum alerta direto de saude fisica foi reportado pelas fontes consultadas.')
    }
    $healthNoteText = @($healthNotes | ForEach-Object { "- $_" }) -join "`r`n"
    $diskRows = @($Diagnostic.DiskHealth.RelevantDisks | Select-Object -First 8 | ForEach-Object {
        $wearText = if ($null -ne $_.DesgastePercentual) { "$($_.DesgastePercentual)% usado" } else { 'Nao informado' }
        $tempText = if ($null -ne $_.TemperaturaC) { "$($_.TemperaturaC) C" } else { 'Nao informada' }
        $readErrors = if ($null -ne $_.ErrosLeitura) { $_.ErrosLeitura } else { 'N/I' }
        $writeErrors = if ($null -ne $_.ErrosEscrita) { $_.ErrosEscrita } else { 'N/I' }

        "Nome: $($_.Nome)`r`n  Tipo/Barramento: $($_.Tipo) / $($_.Barramento)`r`n  Tamanho: $($_.TamanhoGB) GB`r`n  Saude: $($_.Saude)`r`n  Operacional: $($_.Operacional)`r`n  Desgaste: $wearText`r`n  Temperatura: $tempText`r`n  Erros leitura/escrita: $readErrors / $writeErrors"
    }) -join "`r`n`r`n"
    if ([string]::IsNullOrWhiteSpace($diskRows)) {
        $diskRows = 'Dados detalhados de disco nao disponiveis pelas fontes consultadas.'
    }

    $status = if ($diskAlert -or $Diagnostic.DiskUsage.Status -eq 'Critico' -or $Diagnostic.Events.CriticalCount -gt 0) {
        'ATENCAO'
    }
    else {
        'NORMAL'
    }

    $recommendations = @($Diagnostic.Recommendation.Items | ForEach-Object {
        $index = [array]::IndexOf($Diagnostic.Recommendation.Items, $_) + 1
        "$index. $_"
    }) -join "`r`n"

    $report = @"
============================================================
 DIAGNOSTICO HD100 - DISCO 100%
============================================================

Computador:     $($Diagnostic.System.ComputerName)
Windows:        $($Diagnostic.System.WindowsProductName)
Build:          $($Diagnostic.System.WindowsVersion)
Usuario:        $($Diagnostic.System.UserName)
Execucao:       $($Diagnostic.Metadata.StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))
Modo:           $($Diagnostic.Metadata.Mode)

------------------------------------------------------------
 RESUMO
------------------------------------------------------------
Status geral:                    $status
Categoria provavel:              $($Diagnostic.Recommendation.Category)

Disco em 100% sustentado:        $(if ($Diagnostic.DiskUsage.DiskTimePercent -ge 90) { 'Sim' } else { 'Nao/Inconclusivo' })
Uso medio do disco:              $($Diagnostic.DiskUsage.DiskTimePercent)%
Fila media de disco:             $($Diagnostic.DiskUsage.QueueLength)
Processo principal de I/O:       $(if ($topProcess) { "$($topProcess.Name) ($($topProcess.IOTotalMB) MB)" } else { 'Inconclusivo' })
Saude do disco:                  $($Diagnostic.DiskHealth.Status)
Vida util aproximada:            $healthGauge
Eventos criticos de disco:       $($Diagnostic.Events.CriticalCount)
Espaco livre no ${systemDrive}:              $(if ($systemVolume) { "$($systemVolume.FreePercent)%" } else { 'Inconclusivo' })
Integridade Windows:             DISM diagnostico executado; SFC reservado ao modo Assistido
Servicos suspeitos:              $services
Plugins bancarios:               $(if ($Diagnostic.BankPlugins.Detected) { 'Detectado' } else { 'Nao detectado' })
Inicializacao ativa/inativa:      $startupOnCount ON / $startupOffCount OFF
Ultimo boot:                     $lastBoot
Tempo do ultimo boot:            $bootDuration

------------------------------------------------------------
 SAUDE DOS DISCOS
------------------------------------------------------------
Status aproximado:               $healthStatus
Gauge de vida util:              $healthGauge

Dados relevantes:
$diskRows

Observacoes:
$healthNoteText

------------------------------------------------------------
 PROGRAMAS NA INICIALIZACAO
------------------------------------------------------------
$startupRows

------------------------------------------------------------
 RECOMENDACAO
------------------------------------------------------------
$recommendations

------------------------------------------------------------
 ARQUIVOS GERADOS
------------------------------------------------------------
Relatorio TXT:   $($script:HD100Session.TextReportPath)
Diagnostico JSON: $($script:HD100Session.DiagnosticJsonPath)
Logs:            $($script:HD100Session.LogsPath)
"@

    Write-HD100TextFile -Path $script:HD100Session.TextReportPath -Content $report
    return $report
}

function Export-HD100ReportHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Diagnostic)

    $healthSummary = $Diagnostic.DiskHealth.Summary
    $healthPercent = if ($healthSummary -and $null -ne $healthSummary.ApproximateLifePercent) {
        [int]$healthSummary.ApproximateLifePercent
    }
    else {
        0
    }
    $healthStatus = if ($healthSummary) { $healthSummary.Status } else { $Diagnostic.DiskHealth.Status }
    $healthColor = if ($healthPercent -ge 85) {
        '#16a34a'
    }
    elseif ($healthPercent -ge 65) {
        '#ca8a04'
    }
    elseif ($healthPercent -ge 40) {
        '#ea580c'
    }
    else {
        '#dc2626'
    }
    $startupItems = @($Diagnostic.StartupItems)
    $startupOnCount = @($startupItems | Where-Object { $_.Enabled -eq $true }).Count
    $startupOffCount = @($startupItems | Where-Object { $_.Enabled -eq $false }).Count
    $bootDuration = if ($Diagnostic.System.LastBootDurationSeconds) { "$($Diagnostic.System.LastBootDurationSeconds) segundos" } else { 'Nao disponivel' }
    $lastBoot = if ($Diagnostic.System.LastBootUpTime) { ([datetime]$Diagnostic.System.LastBootUpTime).ToString('dd/MM/yyyy HH:mm:ss') } else { 'Nao disponivel' }

    $summaryRows = @(
        @('Computador', $Diagnostic.System.ComputerName),
        @('Windows', $Diagnostic.System.WindowsProductName),
        @('Modo', $Diagnostic.Metadata.Mode),
        @('Categoria provavel', $Diagnostic.Recommendation.Category),
        @('Uso medio de disco', "$($Diagnostic.DiskUsage.DiskTimePercent)%"),
        @('Saude do disco', $Diagnostic.DiskHealth.Status),
        @('Vida util aproximada', "$(if ($healthSummary) { $healthSummary.ApproximateLifePercent } else { 'N/I' })%"),
        @('Inicializacao', "$startupOnCount ON / $startupOffCount OFF"),
        @('Ultimo boot', $lastBoot),
        @('Tempo do ultimo boot', $bootDuration),
        @('Eventos criticos', $Diagnostic.Events.CriticalCount)
    ) | ForEach-Object {
        '<tr class="border-b border-gray-200"><td class="py-2 px-3 font-medium">{0}</td><td class="py-2 px-3">{1}</td></tr>' -f
            (ConvertTo-HtmlSafe -Value $_[0]), (ConvertTo-HtmlSafe -Value $_[1])
    }

    $diskRows = @($Diagnostic.DiskHealth.RelevantDisks | Select-Object -First 8 | ForEach-Object {
        '<tr class="border-b border-gray-200 break-inside-avoid"><td class="py-2 px-3 font-medium">{0}</td><td class="py-2 px-3">{1}</td><td class="py-2 px-3">{2}</td><td class="py-2 px-3 text-right">{3}</td><td class="py-2 px-3">{4}</td><td class="py-2 px-3 text-right">{5}</td><td class="py-2 px-3 text-right">{6}</td></tr>' -f
            (ConvertTo-HtmlSafe -Value $_.Nome),
            (ConvertTo-HtmlSafe -Value $_.Tipo),
            (ConvertTo-HtmlSafe -Value $_.Barramento),
            (ConvertTo-HtmlSafe -Value $_.TamanhoGB),
            (ConvertTo-HtmlSafe -Value $_.Saude),
            (ConvertTo-HtmlSafe -Value $(if ($null -ne $_.DesgastePercentual) { "$($_.DesgastePercentual)%" } else { 'N/I' })),
            (ConvertTo-HtmlSafe -Value $(if ($null -ne $_.TemperaturaC) { "$($_.TemperaturaC) C" } else { 'N/I' }))
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($diskRows)) {
        $diskRows = '<tr><td colspan="7" class="py-3 px-4 text-gray-500">Dados detalhados de disco nao disponiveis.</td></tr>'
    }

    $healthNotes = @($Diagnostic.DiskHealth.Summary.Notes | Select-Object -First 6 | ForEach-Object {
        '<li>{0}</li>' -f (ConvertTo-HtmlSafe -Value $_)
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($healthNotes)) {
        $healthNotes = '<li>Nenhum alerta direto de saude fisica foi reportado pelas fontes consultadas.</li>'
    }

    $startupRows = @($startupItems | Select-Object -First 50 | ForEach-Object {
        $badgeClass = if ($_.Enabled) { 'bg-green-100 text-green-700' } else { 'bg-gray-200 text-gray-600' }
        $stateText = if ($_.Enabled) { 'ON' } else { 'OFF' }
        '<tr class="border-b border-gray-200 break-inside-avoid"><td class="py-2 px-3"><span class="inline-block min-w-12 text-center px-2 py-1 rounded text-xs font-bold {0}">{1}</span></td><td class="py-2 px-3">{2}</td><td class="py-2 px-3">{3}</td><td class="py-2 px-3 font-medium">{4}</td><td class="py-2 px-3 text-xs text-gray-600 break-all">{5}</td></tr>' -f
            $badgeClass,
            $stateText,
            (ConvertTo-HtmlSafe -Value $_.SourceType),
            (ConvertTo-HtmlSafe -Value $_.Scope),
            (ConvertTo-HtmlSafe -Value $_.Name),
            (ConvertTo-HtmlSafe -Value $_.Command)
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($startupRows)) {
        $startupRows = '<tr><td colspan="5" class="py-3 px-4 text-gray-500">Nenhuma entrada de inicializacao encontrada nas fontes consultadas.</td></tr>'
    }

    $topRows = @($Diagnostic.TopIOProcesses | Select-Object -First 10 | ForEach-Object {
        '<tr class="border-b border-gray-200"><td class="py-2 px-3">{0}</td><td class="py-2 px-3">{1}</td><td class="py-2 px-3 text-right">{2}</td></tr>' -f
            (ConvertTo-HtmlSafe -Value $_.Name), (ConvertTo-HtmlSafe -Value $_.Id), (ConvertTo-HtmlSafe -Value $_.IOTotalMB)
    }) -join "`r`n"

    $recommendationRows = @($Diagnostic.Recommendation.Items | ForEach-Object {
        '<li>{0}</li>' -f (ConvertTo-HtmlSafe -Value $_)
    }) -join "`r`n"

    $generatedFileRows = @(
        [pscustomobject]@{ Nome = 'Relatorio TXT'; Caminho = $script:HD100Session.TextReportPath }
        [pscustomobject]@{ Nome = 'Relatorio HTML'; Caminho = $script:HD100Session.HtmlReportPath }
        [pscustomobject]@{ Nome = 'Diagnostico JSON'; Caminho = $script:HD100Session.JsonPath }
        [pscustomobject]@{ Nome = 'Registro de alteracoes'; Caminho = $script:HD100Session.ChangesPath }
        [pscustomobject]@{ Nome = 'Rollback'; Caminho = $script:HD100Session.RollbackPath }
        [pscustomobject]@{ Nome = 'Logs'; Caminho = $script:HD100Session.LogsPath }
        [pscustomobject]@{ Nome = 'Backups'; Caminho = $script:HD100Session.BackupsPath }
    ) | ForEach-Object {
        '<tr class="border-b border-gray-200"><td class="py-2 px-3 font-medium">{0}</td><td class="py-2 px-3 text-xs text-gray-600 break-all">{1}</td></tr>' -f
            (ConvertTo-HtmlSafe -Value $_.Nome),
            (ConvertTo-HtmlSafe -Value $_.Caminho)
    }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Relatorio HD100</title>
    <style>
        @page { size: A4; margin: 15mm; }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            background-color: #f3f4f6;
            color: #1f2937;
            font-family: Arial, Helvetica, sans-serif;
            line-height: 1.45;
        }
        button {
            border: 0;
            cursor: pointer;
            font: inherit;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            vertical-align: top;
        }
        .max-w-4xl { max-width: 56rem; }
        .mx-auto { margin-left: auto; margin-right: auto; }
        .mt-1 { margin-top: .25rem; }
        .mt-2 { margin-top: .5rem; }
        .mt-6 { margin-top: 1.5rem; }
        .mt-10 { margin-top: 2.5rem; }
        .mb-2 { margin-bottom: .5rem; }
        .mb-3 { margin-bottom: .75rem; }
        .mb-4 { margin-bottom: 1rem; }
        .mb-6 { margin-bottom: 1.5rem; }
        .mb-8 { margin-bottom: 2rem; }
        .p-4 { padding: 1rem; }
        .p-10 { padding: 2.5rem; }
        .px-2 { padding-left: .5rem; padding-right: .5rem; }
        .px-3 { padding-left: .75rem; padding-right: .75rem; }
        .px-4 { padding-left: 1rem; padding-right: 1rem; }
        .py-1 { padding-top: .25rem; padding-bottom: .25rem; }
        .py-2 { padding-top: .5rem; padding-bottom: .5rem; }
        .py-3 { padding-top: .75rem; padding-bottom: .75rem; }
        .pt-4 { padding-top: 1rem; }
        .pb-4 { padding-bottom: 1rem; }
        .pl-6 { padding-left: 1.5rem; }
        .flex { display: flex; }
        .inline-block { display: inline-block; }
        .justify-between { justify-content: space-between; }
        .items-center { align-items: center; }
        .items-end { align-items: flex-end; }
        .w-full { width: 100%; }
        .h-4 { height: 1rem; }
        .min-w-12 { min-width: 3rem; }
        .overflow-hidden { overflow: hidden; }
        .break-all { word-break: break-all; }
        .break-inside-avoid { break-inside: avoid; page-break-inside: avoid; }
        .text-left { text-align: left; }
        .text-center { text-align: center; }
        .text-right { text-align: right; }
        .text-xs { font-size: .75rem; }
        .text-sm { font-size: .875rem; }
        .text-xl { font-size: 1.25rem; }
        .text-2xl { font-size: 1.5rem; }
        .text-3xl { font-size: 1.875rem; }
        .font-sans { font-family: Arial, Helvetica, sans-serif; }
        .font-medium { font-weight: 500; }
        .font-semibold { font-weight: 600; }
        .font-bold { font-weight: 700; }
        .uppercase { text-transform: uppercase; }
        .text-white { color: #fff; }
        .text-gray-500 { color: #6b7280; }
        .text-gray-600 { color: #4b5563; }
        .text-gray-700 { color: #374151; }
        .text-gray-800 { color: #1f2937; }
        .text-gray-900 { color: #111827; }
        .text-green-700 { color: #15803d; }
        .bg-white { background-color: #fff; }
        .bg-blue-600 { background-color: #2563eb; }
        .bg-gray-100 { background-color: #f3f4f6; }
        .bg-gray-200 { background-color: #e5e7eb; }
        .bg-green-100 { background-color: #dcfce7; }
        .border { border: 1px solid #e5e7eb; }
        .border-b { border-bottom: 1px solid #e5e7eb; }
        .border-t { border-top: 1px solid #d1d5db; }
        .border-b-2 { border-bottom: 2px solid #d1d5db; }
        .border-gray-200 { border-color: #e5e7eb; }
        .border-gray-300 { border-color: #d1d5db; }
        .rounded { border-radius: .25rem; }
        .shadow { box-shadow: 0 1px 3px rgba(0,0,0,.14); }
        .shadow-lg { box-shadow: 0 10px 15px rgba(0,0,0,.12); }
        .transition { transition: background-color .15s ease-in-out; }
        .hover\:bg-blue-700:hover { background-color: #1d4ed8; }
        .list-disc { list-style-type: disc; }
        .list-decimal { list-style-type: decimal; }
        .space-y-1 > * + * { margin-top: .25rem; }
        @media print {
            body {
                background-color: white;
                color: #000;
            }
            .print\:hidden { display: none !important; }
            .print\:shadow-none { box-shadow: none !important; }
            .print\:m-0 { margin: 0 !important; }
            .print\:p-0 { padding: 0 !important; }
            .print\:max-w-full { max-width: none !important; }
            .print\:text-black { color: #000 !important; }
            * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
        }
    </style>
</head>
<body class="text-gray-800 font-sans print:text-black">
    <div class="max-w-4xl mx-auto mt-6 mb-2 text-right print:hidden">
        <button onclick="window.print()" class="bg-blue-600 text-white px-4 py-2 rounded shadow hover:bg-blue-700 transition">Imprimir Relatorio</button>
    </div>
    <div class="max-w-4xl mx-auto p-10 bg-white shadow-lg print:shadow-none print:m-0 print:p-0 print:max-w-full">
        <header class="flex justify-between items-center border-b-2 border-gray-300 pb-4 mb-6">
            <div>
                <h1 class="text-3xl font-bold text-gray-900">Diagnostico HD100</h1>
                <p class="text-sm text-gray-500 mt-1">Gerado em: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))</p>
            </div>
            <div class="text-right">
                <p class="font-bold">WBA Windows Toolkit</p>
                <p class="text-sm text-gray-500">Disco 100%</p>
            </div>
        </header>

        <main>
            <h2 class="text-xl font-bold mb-3">Resumo executivo</h2>
            <table class="w-full text-left border-collapse mb-8">
                <tbody>
                    $($summaryRows -join "`r`n")
                </tbody>
            </table>

            <h2 class="text-xl font-bold mb-3">Saude dos discos</h2>
            <div class="mb-4 border border-gray-200 rounded p-4 break-inside-avoid">
                <div class="flex justify-between items-end mb-2">
                    <div>
                        <p class="text-sm text-gray-500">Vida util aproximada</p>
                        <p class="text-2xl font-bold text-gray-900">$healthPercent%</p>
                    </div>
                    <p class="font-semibold" style="color: $healthColor">$((ConvertTo-HtmlSafe -Value $healthStatus))</p>
                </div>
                <div class="w-full h-4 bg-gray-200 rounded overflow-hidden">
                    <div class="h-4" style="width: $healthPercent%; background-color: $healthColor"></div>
                </div>
                <p class="text-xs text-gray-500 mt-2">Estimativa baseada nos dados que o Windows expôs: SMART, HealthStatus, Status CIM e contadores de confiabilidade.</p>
            </div>
            <table class="w-full text-left border-collapse mb-4">
                <thead><tr class="bg-gray-100 text-gray-700 uppercase text-sm border-b-2 border-gray-300"><th class="py-3 px-4">Disco</th><th class="py-3 px-4">Tipo</th><th class="py-3 px-4">Barramento</th><th class="py-3 px-4 text-right">GB</th><th class="py-3 px-4">Saude</th><th class="py-3 px-4 text-right">Desgaste</th><th class="py-3 px-4 text-right">Temp.</th></tr></thead>
                <tbody>$diskRows</tbody>
            </table>
            <ul class="list-disc pl-6 mb-8 text-sm text-gray-600">$healthNotes</ul>

            <h2 class="text-xl font-bold mb-3">Programas na inicializacao</h2>
            <table class="w-full text-left border-collapse mb-8">
                <thead><tr class="bg-gray-100 text-gray-700 uppercase text-sm border-b-2 border-gray-300"><th class="py-3 px-4">Estado</th><th class="py-3 px-4">Origem</th><th class="py-3 px-4">Escopo</th><th class="py-3 px-4">Nome</th><th class="py-3 px-4">Comando</th></tr></thead>
                <tbody>$startupRows</tbody>
            </table>

            <h2 class="text-xl font-bold mb-3">Top processos por I/O</h2>
            <table class="w-full text-left border-collapse mb-8">
                <thead><tr class="bg-gray-100 text-gray-700 uppercase text-sm border-b-2 border-gray-300"><th class="py-3 px-4">Processo</th><th class="py-3 px-4">PID</th><th class="py-3 px-4 text-right">I/O MB</th></tr></thead>
                <tbody>$topRows</tbody>
            </table>

            <h2 class="text-xl font-bold mb-3">Recomendacoes</h2>
            <ol class="list-decimal pl-6 space-y-1">$recommendationRows</ol>

            <h2 class="text-xl font-bold mt-10 mb-3">Arquivos gerados</h2>
            <table class="w-full text-left border-collapse">
                <tbody>$($generatedFileRows -join "`r`n")</tbody>
            </table>
        </main>

        <footer class="mt-10 pt-4 border-t border-gray-300 text-center text-sm text-gray-500">
            <p>Documento gerado localmente pelo WBA Windows Toolkit.</p>
        </footer>
    </div>
</body>
</html>
"@

    $encoding = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($script:HD100Session.HtmlReportPath, $html, $encoding)
}

function Invoke-HD100Rollback {
    [CmdletBinding()]
    param()

    Write-Title 'WBA Windows Toolkit - Rollback HD100'
    $items = @(Get-HD100ManagedDisabledStartupItems)
    if (@($items).Count -eq 0) {
        Write-Info 'Nenhuma entrada de inicializacao desabilitada pelo HD100 foi encontrada.'
        return
    }

    Show-HD100StartupItems -Items $items
    if (-not (Confirm-HD100Action -Question "Reativar $(@($items).Count) entrada(s) de inicializacao desabilitada(s) pelo HD100?")) {
        Write-Warn 'Rollback cancelado pelo operador.'
        return
    }

    foreach ($item in $items) {
        try {
            Enable-HD100StartupItem -Item $item
        }
        catch {
            Write-HD100Log -Level 'ERROR' -Message "Falha no rollback da inicializacao '$($item.Name)': $($_.Exception.Message)"
        }
    }
}

function Get-HD100LatestSessionPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$BasePath)

    $root = Get-ToolkitReportsRoot -Path $BasePath
    $modulePath = Join-Path $root 'HD100'

    if (-not (Test-Path -LiteralPath $modulePath)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $modulePath -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Invoke-HD100ReportMode {
    [CmdletBinding()]
    param()

    $latest = Get-HD100LatestSessionPath -BasePath $Path
    if (-not $latest) {
        throw "Nenhuma execucao anterior encontrada em $Path"
    }

    $jsonPath = Join-Path $latest 'diagnostico.json'
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        throw "Arquivo diagnostico.json nao encontrado em $latest"
    }

    $script:HD100Session = [pscustomobject]@{
        StartedAt = Get-Date
        Mode = 'Relatorio'
        ReportsRoot = (Get-ToolkitReportsRoot -Path $Path)
        BasePath = (Split-Path -Parent $latest)
        Path = $latest
        LogsPath = Join-Path $latest 'logs'
        BackupsPath = Join-Path $latest 'backups'
        TextReportPath = Join-Path $latest 'relatorio-hd100.txt'
        HtmlReportPath = Join-Path $latest 'relatorio-hd100.html'
        DiagnosticJsonPath = $jsonPath
        ChangesJsonPath = Join-Path $latest 'alteracoes.json'
        RollbackJsonPath = Join-Path $latest 'rollback.json'
    }

    $diagnostic = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    $text = Export-HD100ReportText -Diagnostic $diagnostic
    if ($GerarHtml) {
        Export-HD100ReportHtml -Diagnostic $diagnostic
    }

    Write-Host $text
}

if ($Modo -eq 'Relatorio') {
    Invoke-HD100ReportMode
    exit 0
}

if (-not (Test-HD100Windows)) {
    throw 'Este script foi projetado para Windows 10/11.'
}

if (-not (Test-IsAdministrator)) {
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

Write-Title 'WBA Windows Toolkit - Diagnostico HD100'
Write-Info "Modo: $Modo"
Write-Info "Versao: $ScriptVersion"

$script:HD100Session = Initialize-HD100Session -BasePath $Path -ExecutionMode $Modo
Write-Info "Diretorio da execucao: $($script:HD100Session.Path)"

if ($Modo -eq 'Rollback') {
    Invoke-HD100Rollback
    exit 0
}

$diagnostic = Invoke-HD100Diagnostic
Export-HD100Json -Diagnostic $diagnostic
$textReport = Export-HD100ReportText -Diagnostic $diagnostic

if ($GerarHtml) {
    Export-HD100ReportHtml -Diagnostic $diagnostic
}

Write-Host $textReport
Write-Ok "Relatorio TXT: $($script:HD100Session.TextReportPath)"
Write-Ok "Diagnostico JSON: $($script:HD100Session.DiagnosticJsonPath)"
if ($GerarHtml) {
    Write-Ok "Relatorio HTML: $($script:HD100Session.HtmlReportPath)"
}
