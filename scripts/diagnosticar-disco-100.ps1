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

.PARAMETER Help
    Exibe a ajuda resumida do script e encerra.

.USO
    Execucao diagnostica padrao:
        .\diagnosticar-disco-100.ps1

    Execucao diagnostica com HTML:
        .\diagnosticar-disco-100.ps1 -GerarHtml

    Modo assistido para reparos seguros:
        .\diagnosticar-disco-100.ps1 -Modo Assistido -GerarHtml

    Simulacao sem executar comandos externos:
        .\diagnosticar-disco-100.ps1 -DryRun

    Gerar relatorio a partir da execucao mais recente:
        .\diagnosticar-disco-100.ps1 -Modo Relatorio -GerarHtml

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
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
    [string]$Path,

    [switch]$Help
)
    [switch]$Version

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null }
catch { Write-Verbose "Nao foi possivel ajustar a pagina de codigo do console para UTF-8: $($_.Exception.Message)" }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot      = Split-Path -Parent $PSScriptRoot
$coreModuleRoot   = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$startupModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Startup'

foreach ($moduleRoot in @($coreModuleRoot, $startupModuleRoot)) {
    if (-not (Test-Path -LiteralPath $moduleRoot)) {
        throw "Modulo nao encontrado: $moduleRoot"
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot, $startupModuleRoot)) {
        foreach ($sub in @('Private', 'Public')) {
            $dir = Join-Path $moduleRoot $sub
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
            }
        }
    }
}
catch {
    throw "Nao foi possivel carregar os modulos do toolkit: $($_.Exception.Message)"
}

$ScriptVersion = 'v1.0.0'
$script:HD100Session = $null
$script:HD100Changes = [System.Collections.ArrayList]::new()

# WBA-DOCS: Category=Maintenance; Related=limpar-windows.ps1; Manual=Diagnostico assistido de Disco 100%

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
        [Parameter(Mandatory = $false)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ExecutionMode
    )

    $s = Initialize-ScriptSession -ModuleName 'diagnostico-hd100' -BasePath $BasePath -ExecutionMode $ExecutionMode
    $s | Add-Member -MemberType NoteProperty -Name 'TextReportPath'     -Value (Join-Path $s.Path 'relatorio-hd100.txt')
    $s | Add-Member -MemberType NoteProperty -Name 'HtmlReportPath'     -Value (Join-Path $s.Path 'relatorio-hd100.html')
    $s | Add-Member -MemberType NoteProperty -Name 'DiagnosticJsonPath' -Value (Join-Path $s.Path 'diagnostico.json')
    $s | Add-Member -MemberType NoteProperty -Name 'ChangesJsonPath'    -Value (Join-Path $s.Path 'alteracoes.json')
    $s | Add-Member -MemberType NoteProperty -Name 'RollbackJsonPath'   -Value (Join-Path $s.Path 'rollback.json')
    return $s
}

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Diagnostico de Disco 100% — $script:ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$script:ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Modo <modo>           Diagnostico (padrao), Assistido, Relatorio ou Rollback."
    Write-Host "  -DryRun                Simula a execucao sem chamar CHKDSK, DISM ou SFC."
    Write-Host "  -GerarHtml             Gera relatorio HTML alem do TXT e JSON."
    Write-Host "  -GerarJson             Compatibilidade — o JSON ja e gerado por padrao."
    Write-Host "  -AgendarChkdsk         No modo Assistido, oferece agendamento de CHKDSK /R."
    Write-Host "  -CriarPontoRestauracao Reservado ao modo Assistido; exige confirmacao."
    Write-Host "  -DiretorioSaida '<dir>' Raiz de relatorios. Padrao: ReportsRoot persistente ou C:\WBA\Relatorios"
    Write-Host "  -Help                  Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$script:ScriptName"
    Write-Host "  .\$script:ScriptName -GerarHtml"
    Write-Host "  .\$script:ScriptName -Modo Assistido -GerarHtml"
    Write-Host ""
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
                try { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
                catch { Write-Verbose "Nao foi possivel remover arquivo temporario '$path': $($_.Exception.Message)" }
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

    try { $computerInfo = Get-ComputerInfo -ErrorAction Stop }
    catch { Write-Verbose "Get-ComputerInfo indisponivel: $($_.Exception.Message)" }
    try { $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop }
    catch { Write-Verbose "Nao foi possivel consultar Win32_OperatingSystem: $($_.Exception.Message)" }
    try { $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop }
    catch { Write-Verbose "Nao foi possivel consultar Win32_ComputerSystem: $($_.Exception.Message)" }
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop }
    catch { Write-Verbose "Nao foi possivel consultar Win32_BIOS: $($_.Exception.Message)" }
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
        catch {
            Write-Verbose "Contador de confiabilidade indisponivel para '$($disk.FriendlyName)': $($_.Exception.Message)"
        }
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

    try { $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size) }
    catch { Write-Verbose "Get-PhysicalDisk indisponivel: $($_.Exception.Message)" }
    try { $disks = @(Get-Disk -ErrorAction Stop | Select-Object Number, FriendlyName, BusType, HealthStatus, OperationalStatus, PartitionStyle, Size) }
    catch { Write-Verbose "Get-Disk indisponivel: $($_.Exception.Message)" }
    try { $diskDrives = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Select-Object Model, InterfaceType, MediaType, Status, Size, SerialNumber) }
    catch { Write-Verbose "Win32_DiskDrive indisponivel: $($_.Exception.Message)" }
    try { $smart = @(Get-CimInstance -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop | Select-Object InstanceName, PredictFailure, Reason) }
    catch { Write-Verbose "Dados SMART indisponiveis: $($_.Exception.Message)" }
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

    if ($DryRun) {
        Write-HD100Log -Message 'DRY-RUN: agendamento de CHKDSK /R simulado (nenhum comando executado).'
        return [pscustomobject]@{ Scheduled = $false; Reason = 'DryRun.' }
    }

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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Item
    )

    if (-not $PSCmdlet.ShouldProcess((@($Item | ForEach-Object Name) -join ', '), 'Remover item de inicializacao')) {
        return @()
    }

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

    $patterns = @('Warsaw', 'Topaz', 'GBPlugin', 'GAS Tecnologia', 'core', 'Diebold', 'Guardiao', 'Guardião')
    $processes = @()
    $services = @()
    try {
        $processes = @(Get-Process -ErrorAction Stop | Where-Object {
            $name = $_.Name
            $patterns | Where-Object { $name -match [regex]::Escape($_) }
        } | Select-Object Name, Id, Path)
    }
    catch { Write-Verbose "Nao foi possivel consultar processos de plugins bancarios: $($_.Exception.Message)" }
    try {
        $services = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {
            $text = "$($_.Name) $($_.DisplayName) $($_.PathName)"
            $patterns | Where-Object { $text -match [regex]::Escape($_) }
        } | Select-Object Name, DisplayName, State, StartMode, PathName)
    }
    catch { Write-Verbose "Nao foi possivel consultar servicos de plugins bancarios: $($_.Exception.Message)" }

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

    $processes = @()
    try {
        $processes = @(Get-Process -Name OneDrive -ErrorAction Stop | Select-Object Name, Id, Path,
            @{Name = 'IOTotalMB'; Expression = { [math]::Round(($_.IOReadBytes + $_.IOWriteBytes) / 1MB, 2) } })
    }
    catch { Write-Verbose "OneDrive nao esta em execucao ou nao pode ser consultado: $($_.Exception.Message)" }

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
        catch {
            Write-Verbose "Chave de inicializacao '$path' indisponivel: $($_.Exception.Message)"
        }
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
    $processes = @()
    try {
        $processes = @(Get-Process -ErrorAction Stop | Where-Object { $_.Name -in $browserProcesses } |
            Select-Object Name, Id, Path,
                @{Name = 'IOTotalMB'; Expression = { [math]::Round(($_.IOReadBytes + $_.IOWriteBytes) / 1MB, 2) } })
    }
    catch { Write-Verbose "Nao foi possivel consultar processos de navegadores: $($_.Exception.Message)" }

    return [pscustomobject]@{
        Processes = @($processes)
        Detected = @($processes).Count -gt 0
    }
}

function Get-HD100AdobeReader {
    [CmdletBinding()]
    param()

    $processes = @()
    try { $processes = @(Get-Process -ErrorAction Stop | Where-Object { $_.Name -match 'AcroRd|Acrobat' } | Select-Object Name, Id, Path) }
    catch { Write-Verbose "Nao foi possivel consultar processos do Adobe Reader: $($_.Exception.Message)" }
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
        Write-TextFileUtf8 -Path (Join-Path $script:HD100Session.LogsPath 'eventos-disco.log') -Content (($events.Events | Format-List | Out-String))
    }
    catch {
        Write-HD100Log -Level 'WARN' -Message "Nao foi possivel gravar o log de eventos de disco: $($_.Exception.Message)"
    }

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

    Write-TextFileUtf8 -Path $script:HD100Session.DiagnosticJsonPath -Content ($Diagnostic | ConvertTo-Json -Depth 8)
    Write-TextFileUtf8 -Path $script:HD100Session.ChangesJsonPath -Content (@($script:HD100Changes) | ConvertTo-Json -Depth 6)
    Write-TextFileUtf8 -Path $script:HD100Session.RollbackJsonPath -Content (@($script:HD100Changes | Where-Object { $_.Reversivel }) | ConvertTo-Json -Depth 6)
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
        '<tr><th>{0}</th><td>{1}</td></tr>' -f
            (ConvertTo-HtmlSafe -Value $_[0]), (ConvertTo-HtmlSafe -Value $_[1])
    }

    $diskRows = @($Diagnostic.DiskHealth.RelevantDisks | Select-Object -First 8 | ForEach-Object {
        '<tr><td><strong>{0}</strong></td><td>{1}</td><td>{2}</td><td style="text-align:right">{3}</td><td>{4}</td><td style="text-align:right">{5}</td><td style="text-align:right">{6}</td></tr>' -f
            (ConvertTo-HtmlSafe -Value $_.Nome),
            (ConvertTo-HtmlSafe -Value $_.Tipo),
            (ConvertTo-HtmlSafe -Value $_.Barramento),
            (ConvertTo-HtmlSafe -Value $_.TamanhoGB),
            (ConvertTo-HtmlSafe -Value $_.Saude),
            (ConvertTo-HtmlSafe -Value $(if ($null -ne $_.DesgastePercentual) { "$($_.DesgastePercentual)%" } else { 'N/I' })),
            (ConvertTo-HtmlSafe -Value $(if ($null -ne $_.TemperaturaC) { "$($_.TemperaturaC) C" } else { 'N/I' }))
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($diskRows)) {
        $diskRows = '<tr><td colspan="7" class="muted">Dados detalhados de disco nao disponiveis.</td></tr>'
    }

    $healthNotes = @($Diagnostic.DiskHealth.Summary.Notes | Select-Object -First 6 | ForEach-Object {
        '<li>{0}</li>' -f (ConvertTo-HtmlSafe -Value $_)
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($healthNotes)) {
        $healthNotes = '<li>Nenhum alerta direto de saude fisica foi reportado pelas fontes consultadas.</li>'
    }

    $startupRows = @($startupItems | Select-Object -First 50 | ForEach-Object {
        $badgeClass = if ($_.Enabled) { 'badge-green' } else { 'badge-gray' }
        $stateText = if ($_.Enabled) { 'ON' } else { 'OFF' }
        '<tr><td><span class="badge {0}" style="min-width:3rem;text-align:center">{1}</span></td><td>{2}</td><td>{3}</td><td><strong>{4}</strong></td><td class="mono">{5}</td></tr>' -f
            $badgeClass,
            $stateText,
            (ConvertTo-HtmlSafe -Value $_.SourceType),
            (ConvertTo-HtmlSafe -Value $_.Scope),
            (ConvertTo-HtmlSafe -Value $_.Name),
            (ConvertTo-HtmlSafe -Value $_.Command)
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($startupRows)) {
        $startupRows = '<tr><td colspan="5" class="muted">Nenhuma entrada de inicializacao encontrada nas fontes consultadas.</td></tr>'
    }

    $topRows = @($Diagnostic.TopIOProcesses | Select-Object -First 10 | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td style="text-align:right">{2}</td></tr>' -f
            (ConvertTo-HtmlSafe -Value $_.Name), (ConvertTo-HtmlSafe -Value $_.Id), (ConvertTo-HtmlSafe -Value $_.IOTotalMB)
    }) -join "`r`n"

    $recommendationRows = @($Diagnostic.Recommendation.Items | ForEach-Object {
        '<li>{0}</li>' -f (ConvertTo-HtmlSafe -Value $_)
    }) -join "`r`n"

    $generatedFileRows = @(
        [pscustomobject]@{ Nome = 'Relatorio TXT'; Caminho = $script:HD100Session.TextReportPath }
        [pscustomobject]@{ Nome = 'Relatorio HTML'; Caminho = $script:HD100Session.HtmlReportPath }
        [pscustomobject]@{ Nome = 'Diagnostico JSON'; Caminho = $script:HD100Session.DiagnosticJsonPath }
        [pscustomobject]@{ Nome = 'Registro de alteracoes'; Caminho = $script:HD100Session.ChangesJsonPath }
        [pscustomobject]@{ Nome = 'Rollback'; Caminho = $script:HD100Session.RollbackJsonPath }
        [pscustomobject]@{ Nome = 'Logs'; Caminho = $script:HD100Session.LogsPath }
        [pscustomobject]@{ Nome = 'Backups'; Caminho = $script:HD100Session.BackupsPath }
    ) | ForEach-Object {
        '<tr><th>{0}</th><td class="mono">{1}</td></tr>' -f
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
@font-face{font-family:'Inter';font-style:normal;font-weight:400;font-display:swap;src:local('Inter Regular'),local('Segoe UI'),local('sans-serif')}
@font-face{font-family:'Inter';font-style:normal;font-weight:700;font-display:swap;src:local('Inter Bold'),local('Segoe UI Bold'),local('sans-serif')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:400;font-display:swap;src:local('JetBrains Mono Regular'),local('Consolas'),local('monospace')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:700;font-display:swap;src:local('JetBrains Mono Bold'),local('Consolas Bold'),local('monospace')}
:root{--primary:#1e3a5f;--primary-lt:#2d5986;--accent:#2563eb;--success:#16a34a;--warning:#d97706;--danger:#dc2626;--bg:#f0f4f8;--surface:#fff;--border:#e2e8f0;--text:#1e293b;--muted:#64748b;--radius:8px;--font-sans:'Inter','Segoe UI',system-ui,-apple-system,sans-serif;--font-mono:'JetBrains Mono','Consolas',ui-monospace,monospace}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{font-family:var(--font-sans);background:var(--bg);color:var(--text);font-size:14px;line-height:1.5}
header{background:linear-gradient(135deg,var(--primary) 0%,var(--primary-lt) 100%);color:#fff;padding:2rem 2.5rem;display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:1rem}
header .title-block h1{font-size:1.6rem;font-weight:700;letter-spacing:-0.02em}
header .title-block p{opacity:.75;font-size:.85rem;margin-top:.25rem}
header .meta-block{text-align:right;font-size:.8rem;opacity:.8;line-height:1.8}
main{max-width:1100px;margin:1.5rem auto;padding:0 1.5rem}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:1rem;margin-bottom:1.5rem}
.card{background:var(--surface);border-radius:var(--radius);padding:1.1rem 1.25rem;box-shadow:0 1px 6px rgba(0,0,0,.07);border-left:4px solid var(--accent);transition:box-shadow .15s}
.card:hover{box-shadow:0 4px 14px rgba(0,0,0,.12)}
.card-icon{font-size:1.4rem;margin-bottom:.4rem}
.card-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:600}
.card-value{font-size:1.05rem;font-weight:700;color:var(--primary);margin-top:.2rem}
.card-sub{font-size:.75rem;color:var(--muted);margin-top:.15rem}
.section{background:var(--surface);border-radius:var(--radius);box-shadow:0 1px 6px rgba(0,0,0,.07);margin-bottom:1.25rem;overflow:hidden}
.section-hdr{background:var(--primary);color:#fff;padding:.75rem 1.5rem;font-size:.9rem;font-weight:700;display:flex;align-items:center;gap:.5rem}
.section-body{padding:1.25rem 1.5rem}
h2{font-size:1rem;font-weight:700;color:var(--text);margin:1.5rem 0 .75rem;padding-bottom:.5rem;border-bottom:1px solid var(--border)}
.data-table{width:100%;border-collapse:collapse;font-size:.82rem}
.data-table thead th{background:#f8fafc;color:var(--primary);font-weight:700;padding:.55rem 1rem;text-align:left;border-bottom:2px solid var(--border);white-space:nowrap}
.data-table tbody td{padding:.5rem 1rem;border-bottom:1px solid #f1f5f9}
.data-table tbody tr:last-child td{border-bottom:none}
.data-table tbody tr:hover td{background:#f8faff}
.kv-table{width:100%;border-collapse:collapse}
.kv-table th{width:220px;font-weight:600;font-size:.8rem;color:var(--muted);text-align:left;padding:.4rem .75rem .4rem 0;border-bottom:1px solid var(--border);vertical-align:top}
.kv-table td{font-size:.85rem;padding:.4rem 0;border-bottom:1px solid var(--border)}
.kv-table tr:last-child th,.kv-table tr:last-child td{border-bottom:none}
.badge{display:inline-block;padding:.15em .55em;border-radius:4px;font-size:.72rem;font-weight:700;white-space:nowrap}
.badge-green{background:#dcfce7;color:#15803d}
.badge-yellow{background:#fef9c3;color:#92400e}
.badge-red{background:#fee2e2;color:#991b1b}
.badge-blue{background:#dbeafe;color:#1e40af}
.badge-gray{background:#f1f5f9;color:#475569}
.disk-bar{background:#e2e8f0;border-radius:4px;height:10px;overflow:hidden}
.disk-fill{height:100%;border-radius:4px;transition:width .3s}
.bar-ok{background:var(--success)}
.bar-warn{background:var(--warning)}
.bar-danger{background:var(--danger)}
.muted{color:var(--muted)}
.small{font-size:11px}
.mono{font-family:var(--font-mono);font-size:.8rem;word-break:break-all}
.link-btn{display:inline-block;padding:.4rem .75rem;background:var(--accent);color:#fff;font-size:.75rem;font-weight:600;border-radius:4px;text-decoration:none;transition:background .15s}
.link-btn:hover{background:#1d4ed8}
.toolbar{max-width:1100px;margin:0 auto;padding:0 1.5rem;text-align:right}
button{border:0;border-radius:4px;background:var(--accent);color:#fff;cursor:pointer;font:inherit;padding:8px 14px;transition:background .15s}
button:hover{background:#1d4ed8}
footer{text-align:center;color:var(--muted);font-size:.78rem;padding:1.5rem;margin-top:.5rem}
@page{size:A4;margin:15mm}
@media print{body{background:#fff;font-size:11px}header,.section-hdr{print-color-adjust:exact;-webkit-print-color-adjust:exact}.toolbar{display:none}*{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style>
</head>
<body>
    <div class="toolbar">
        <button onclick="window.print()">Imprimir Relatorio</button>
    </div>
    <header>
        <div class="title-block">
            <h1>&#128190; Diagnostico HD100</h1>
            <p>Gerado em: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))</p>
        </div>
        <div class="meta-block">
            <div><strong>WBA Windows Toolkit</strong></div>
            <div>Disco 100%</div>
        </div>
    </header>
    <main>
        <div class="section">
            <div class="section-hdr">&#128203; Resumo Executivo</div>
            <div class="section-body">
                <table class="kv-table">
                    $($summaryRows -join "`r`n")
                </table>
            </div>
        </div>

        <div class="section">
            <div class="section-hdr">&#128190; Saude dos Discos</div>
            <div class="section-body">
                <div class="cards" style="margin-bottom:1rem">
                    <div class="card" style="border-left-color:$healthColor">
                        <div class="card-label">Vida Util Aproximada</div>
                        <div class="card-value" style="color:$healthColor">$healthPercent%</div>
                        <div class="card-sub">$((ConvertTo-HtmlSafe -Value $healthStatus))</div>
                    </div>
                </div>
                <div class="disk-bar" style="margin-bottom:1rem"><div class="disk-fill" style="width:$healthPercent%;background:$healthColor"></div></div>
                <p class="muted small" style="margin-bottom:1rem">Estimativa baseada nos dados que o Windows expos: SMART, HealthStatus, Status CIM e contadores de confiabilidade.</p>
                <table class="data-table">
                    <thead><tr><th>Disco</th><th>Tipo</th><th>Barramento</th><th style="text-align:right">GB</th><th>Saude</th><th style="text-align:right">Desgaste</th><th style="text-align:right">Temp.</th></tr></thead>
                    <tbody>$diskRows</tbody>
                </table>
                <ul style="margin-top:1rem;padding-left:1.2rem;color:var(--muted);font-size:.82rem">$healthNotes</ul>
            </div>
        </div>

        <div class="section">
            <div class="section-hdr">&#128187; Programas na Inicializacao</div>
            <div class="section-body">
                <table class="data-table">
                    <thead><tr><th>Estado</th><th>Origem</th><th>Escopo</th><th>Nome</th><th>Comando</th></tr></thead>
                    <tbody>$startupRows</tbody>
                </table>
            </div>
        </div>

        <div class="section">
            <div class="section-hdr">&#9881; Top Processos por I/O</div>
            <div class="section-body">
                <table class="data-table">
                    <thead><tr><th>Processo</th><th>PID</th><th style="text-align:right">I/O MB</th></tr></thead>
                    <tbody>$topRows</tbody>
                </table>
            </div>
        </div>

        <div class="section">
            <div class="section-hdr">&#128161; Recomendacoes</div>
            <div class="section-body">
                <ol style="margin:0;padding-left:1.2rem;line-height:1.8">$recommendationRows</ol>
            </div>
        </div>

        <div class="section">
            <div class="section-hdr">&#128196; Arquivos Gerados</div>
            <div class="section-body">
                <table class="kv-table">
                    <tbody>$($generatedFileRows -join "`r`n")</tbody>
                </table>
            </div>
        </div>
    </main>
    <footer>
        Documento gerado localmente pelo WBA Windows Toolkit.
    </footer>
</body>
</html>
"@

    $encoding = [System.Text.UTF8Encoding]::new($true)
        Write-TextFileUtf8 -Path $script:HD100Session.HtmlReportPath -Content $html
}

function Invoke-HD100Rollback {
    [CmdletBinding()]
    param()

    Write-Title 'WBA Windows Toolkit - Rollback HD100'
    $items = @(Get-HD100StartupItems | Where-Object { $_.ManagedDisabled })
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
    $modulePath = Join-Path $root 'diagnostico-hd100'

    if (-not (Test-Path -LiteralPath $modulePath)) {
        return $null
    }

    try {
        return Get-ChildItem -LiteralPath $modulePath -Directory -ErrorAction Stop |
            Sort-Object Name -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
    catch {
        Write-Verbose "Nao foi possivel listar sessoes de diagnostico: $($_.Exception.Message)"
        return $null
    }
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

if ($Help) { Show-Help; exit 0 }
if ($Version) { Write-Host "Script: $ScriptName — $ScriptVersion" -ForegroundColor Green; exit 0 }

if ($Modo -eq 'Relatorio') {
    Invoke-HD100ReportMode
    exit 0
}

if (-not (Test-HD100Windows)) {
    throw 'Este script foi projetado para Windows 10/11.'
}

if (-not (Test-IsAdministrator)) {
    $relaunchCommand = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunchCommand) -Verb RunAs
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
