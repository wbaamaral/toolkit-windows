#requires -version 5.1
<#
.SYNOPSIS
    Backup e restauracao de drivers de terceiros instalados no Windows.

.DESCRIPTION
    Enumera drivers OEM (nao-inbox) do sistema, permite selecao granular e executa
    exportacao via pnputil. No modo Restore, verifica presenca do hardware antes de
    instalar; drivers sem hardware detectado exigem confirmacao explicita do operador
    com aviso de risco de instabilidade.

.PARAMETER Modo
    Define a operacao:
      Backup  - enumera e exporta drivers instalados (padrao)
      Restore - localiza backup anterior e reinstala drivers selecionados

.PARAMETER DryRun
    Simula operacoes sem executar pnputil. Exibe o que seria feito.

.PARAMETER GerarHtml
    Gera relatorio HTML alem do TXT.

.PARAMETER Path
    Raiz de relatorios/backup. Quando omitido, usa configuracao do toolkit ou C:\WBA\Relatorios.

.USO
    Backup interativo (padrao):
        .\Backup-Restaurar-Drivers.ps1

    Backup simulado:
        .\Backup-Restaurar-Drivers.ps1 -DryRun

    Restore interativo com HTML:
        .\Backup-Restaurar-Drivers.ps1 -Modo Restore -GerarHtml

    Path customizado:
        .\Backup-Restaurar-Drivers.ps1 -Path "D:\Backup\Drivers"

.NOTAS
    Requer PowerShell 5.1 e execucao como Administrador.
    Get-WindowsDriver requer o modulo DISM, presente em Windows 8.1+ e Server 2012+.
    Modulo WbaToolkit.Core carregado automaticamente.
#>
param(
    [ValidateSet('Backup', 'Restore')]
    [string]$Modo = 'Backup',

    [switch]$DryRun,

    [switch]$GerarHtml,

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

$ScriptVersion = 'v1.0'
$ToolkitRoot   = Split-Path -Parent $PSScriptRoot

$coreModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $coreModulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Maintenance; Related=Gerenciar-Inicializacao-Windows.ps1; Manual=Backup e restauracao de drivers OEM

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$script:Session        = $null
$script:LogPath        = $null
$script:PnpEntityCache = $null

# ─── helpers locais ──────────────────────────────────────────────────────────

function Write-DrvLog {
    [CmdletBinding()]
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )
    Write-ScriptLog -Message $Message -Level $Level -LogPath $script:LogPath
}

function Write-DrvSection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Host ''
    Write-Host ('--- ' + $Title + ' ---') -ForegroundColor DarkCyan
    Write-DrvLog -Message $Title
}

# ─── enumeracao de drivers (Modo Backup) ─────────────────────────────────────

function Get-ThirdPartyDrivers {
    [CmdletBinding()]
    param()

    Write-DrvLog -Message 'Consultando drivers de terceiros via DISM...'

    $driverList = @()
    try {
        $driverList = @(Get-WindowsDriver -Online -All -ErrorAction Stop |
            Where-Object { $_.Driver -like 'oem*.inf' } |
            Sort-Object ClassName, ProviderName)
    }
    catch {
        Write-DrvLog -Level 'ERROR' -Message "Falha ao consultar Get-WindowsDriver: $($_.Exception.Message)"
        return @()
    }

    if ($driverList.Count -eq 0) { return @() }

    Write-DrvLog -Message "$($driverList.Count) drivers OEM encontrados. Mapeando dispositivos..."

    $pnpSigned = @(Get-CimInstanceSafe -ClassName 'Win32_PnPSignedDriver')
    $pnpEntity = @(Get-CimInstanceSafe -ClassName 'Win32_PnPEntity')

    $results = [System.Collections.ArrayList]::new()

    foreach ($drv in $driverList) {
        $infName         = $drv.Driver
        $matchingDevices = @($pnpSigned | Where-Object { $_.InfName -eq $infName })

        $deviceNames = [System.Collections.ArrayList]::new()
        $hardwareIds = [System.Collections.ArrayList]::new()

        foreach ($dev in $matchingDevices) {
            if ([string]::IsNullOrEmpty($dev.DeviceID)) { continue }
            $entity = $pnpEntity | Where-Object { $_.DeviceID -eq $dev.DeviceID } | Select-Object -First 1
            if (-not $entity) { continue }
            if (-not [string]::IsNullOrEmpty($entity.Name)) {
                $null = $deviceNames.Add($entity.Name)
            }
            if ($entity.HardwareID) {
                foreach ($hwId in $entity.HardwareID) { $null = $hardwareIds.Add($hwId) }
            }
        }

        $dateStr = ''
        if ($drv.Date) {
            try { $dateStr = ([datetime]$drv.Date).ToString('yyyy-MM-dd') } catch { $dateStr = "$($drv.Date)" }
        }

        $null = $results.Add([pscustomobject]@{
            InfOriginal      = $infName
            OriginalFileName = "$($drv.OriginalFileName)"
            Provider         = "$($drv.ProviderName)"
            ClassName        = "$($drv.ClassName)"
            Version          = "$($drv.Version)"
            Date             = $dateStr
            DeviceNames      = @($deviceNames)
            HardwareIds      = @($hardwareIds)
        })
    }

    return @($results)
}

# ─── catalogo de backup (Modo Restore) ───────────────────────────────────────

function Get-BackupDriverCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupSessionPath
    )

    $metaPath = Join-Path $BackupSessionPath 'metadados.json'
    if (-not (Test-Path -LiteralPath $metaPath)) {
        Write-DrvLog -Level 'ERROR' -Message "metadados.json nao encontrado em: $BackupSessionPath"
        return @()
    }

    $json    = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $catalog = $json | ConvertFrom-Json

    $result = [System.Collections.ArrayList]::new()
    foreach ($item in $catalog) {
        $hwIds      = @()
        $devNames   = @()
        if ($item.HardwareIds)  { $hwIds    = @($item.HardwareIds) }
        if ($item.DeviceNames)  { $devNames = @($item.DeviceNames) }

        $null = $result.Add([pscustomobject]@{
            InfOriginal      = "$($item.InfOriginal)"
            OriginalFileName = "$($item.OriginalFileName)"
            Provider         = "$($item.Provider)"
            ClassName        = "$($item.ClassName)"
            Version          = "$($item.Version)"
            Date             = "$($item.Date)"
            DeviceNames      = $devNames
            HardwareIds      = $hwIds
            BackupFolder     = "$($item.BackupFolder)"
            BackupDate       = "$($item.BackupDate)"
            HardwarePresent  = $false
        })
    }
    return @($result)
}

function Find-BackupFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ModulePath
    )

    if (-not (Test-Path -LiteralPath $ModulePath)) {
        return $null
    }

    $candidates = @(Get-ChildItem -Path $ModulePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'metadados.json') } |
        Sort-Object Name -Descending)

    if ($candidates.Count -eq 0) { return $null }
    if ($candidates.Count -eq 1) { return $candidates[0].FullName }

    Write-Host ''
    Write-Host 'Multiplas sessoes de backup encontradas:' -ForegroundColor Cyan
    Write-Host ''
    $idx = 0
    foreach ($c in $candidates) {
        $idx++
        Write-Host ("  {0,3}  {1}" -f $idx, $c.Name)
    }
    Write-Host ''

    while ($true) {
        $rawInput = (Read-Host 'Selecione a sessao de backup [1]').Trim()
        if ($rawInput -eq '') { return $candidates[0].FullName }

        $num = 0
        if ([int]::TryParse($rawInput, [ref]$num) -and $num -ge 1 -and $num -le $candidates.Count) {
            return $candidates[$num - 1].FullName
        }
        Write-Warn "Numero invalido. Selecione entre 1 e $($candidates.Count)."
    }
}

# ─── verificacao de hardware ──────────────────────────────────────────────────

function Test-HardwarePresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$HardwareIds
    )

    if ($HardwareIds.Count -eq 0) { return $false }

    if ($null -eq $script:PnpEntityCache) {
        $script:PnpEntityCache = @(Get-CimInstanceSafe -ClassName 'Win32_PnPEntity')
    }

    foreach ($dev in $script:PnpEntityCache) {
        if (-not $dev.HardwareID) { continue }
        foreach ($hwId in $dev.HardwareID) {
            if ($HardwareIds -contains $hwId) { return $true }
        }
    }
    return $false
}

# ─── exibicao da lista ────────────────────────────────────────────────────────

function Show-DriverList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Drivers,

        [bool]$ShowStatus = $false
    )

    Write-Host ''
    if ($ShowStatus) {
        Write-Host ('{0,-4} {1,-12} {2,-14} {3,-19} {4,-14} {5,-10} {6}' -f
            '#', 'Status', 'Classe', 'Provider', 'Versao', 'Data', 'Dispositivo') -ForegroundColor Cyan
        Write-Host ('{0,-4} {1,-12} {2,-14} {3,-19} {4,-14} {5,-10} {6}' -f
            '---', '----------', '------------', '-----------------', '------------', '--------', '-----------') -ForegroundColor DarkGray
    }
    else {
        Write-Host ('{0,-4} {1,-14} {2,-19} {3,-14} {4,-10} {5}' -f
            '#', 'Classe', 'Provider', 'Versao', 'Data', 'Dispositivo') -ForegroundColor Cyan
        Write-Host ('{0,-4} {1,-14} {2,-19} {3,-14} {4,-10} {5}' -f
            '---', '------------', '-----------------', '------------', '--------', '-----------') -ForegroundColor DarkGray
    }

    $idx = 0
    foreach ($drv in $Drivers) {
        $idx++

        $device = if ($drv.DeviceNames -and $drv.DeviceNames.Count -gt 0) { $drv.DeviceNames[0] } else { '(sem dispositivo)' }
        $prov   = $drv.Provider
        $cls    = $drv.ClassName
        $ver    = $drv.Version

        if ($prov.Length  -gt 17) { $prov  = $prov.Substring(0, 16) + '~' }
        if ($cls.Length   -gt 12) { $cls   = $cls.Substring(0, 11)  + '~' }
        if ($ver.Length   -gt 12) { $ver   = $ver.Substring(0, 11)  + '~' }
        if ($device.Length -gt 36) { $device = $device.Substring(0, 35) + '~' }

        if ($ShowStatus) {
            $hwPresent = $drv.HardwarePresent
            $statusTxt = if ($hwPresent) { 'OK Hardware' } else { 'Ausente' }
            $color     = if ($hwPresent) { 'Green' } else { 'Yellow' }
            Write-Host ('{0,-4} ' -f $idx) -NoNewline
            Write-Host ('{0,-12} ' -f $statusTxt) -NoNewline -ForegroundColor $color
            Write-Host ('{0,-14} {1,-19} {2,-14} {3,-10} {4}' -f $cls, $prov, $ver, $drv.Date, $device)
        }
        else {
            Write-Host ('{0,-4} {1,-14} {2,-19} {3,-14} {4,-10} {5}' -f $idx, $cls, $prov, $ver, $drv.Date, $device)
        }
    }
    Write-Host ''
}

# ─── selecao interativa ───────────────────────────────────────────────────────

function Read-DriverSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Drivers,

        [Parameter(Mandatory = $true)]
        [string]$ActionLabel
    )

    Write-Host "Selecionar drivers para $ActionLabel" -ForegroundColor White
    Write-Host '  [numeros]  ex: 1,3,5   Selecionar individualmente' -ForegroundColor Gray
    Write-Host '  [T]                    Todos' -ForegroundColor Gray
    Write-Host '  [N]                    Cancelar' -ForegroundColor Gray
    Write-Host ''

    while ($true) {
        $rawInput = (Read-Host 'Selecao').Trim()
        if ($rawInput -eq '') { continue }
        if ($rawInput -ieq 'N') { return @() }
        if ($rawInput -ieq 'T') { return $Drivers }

        $parts    = $rawInput -split '[,\s]+'
        $selected = [System.Collections.ArrayList]::new()
        $valid    = $true

        foreach ($part in $parts) {
            $part = $part.Trim()
            if ($part -eq '') { continue }

            $num = 0
            if (-not [int]::TryParse($part, [ref]$num)) {
                Write-Warn "Entrada invalida: '$part'. Use numeros separados por virgula, T ou N."
                $valid = $false
                break
            }
            if ($num -lt 1 -or $num -gt $Drivers.Count) {
                Write-Warn "Numero fora do intervalo: $num (1 a $($Drivers.Count))."
                $valid = $false
                break
            }
            $null = $selected.Add($Drivers[$num - 1])
        }

        if ($valid -and $selected.Count -gt 0) { return @($selected) }
        if ($valid -and $selected.Count -eq 0) { Write-Warn 'Nenhum driver selecionado. Digite numeros, T ou N.' }
    }
}

# ─── backup ───────────────────────────────────────────────────────────────────

function Invoke-DriverBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$SelectedDrivers,

        [Parameter(Mandatory = $true)]
        [string]$DestRoot,

        [bool]$IsDryRun = $false
    )

    $results = [System.Collections.ArrayList]::new()
    $count   = 0

    foreach ($drv in $SelectedDrivers) {
        $count++

        $provSlug  = ($drv.Provider  -replace '[^a-zA-Z0-9]', '_') -replace '_+', '_'
        $classSlug = ($drv.ClassName -replace '[^a-zA-Z0-9]', '_') -replace '_+', '_'
        $infSlug   = $drv.InfOriginal -replace '\.inf$', ''
        $folderName = ('{0}_{1}_{2}' -f $infSlug, $provSlug, $classSlug)
        if ($folderName.Length -gt 80) { $folderName = $folderName.Substring(0, 80) }

        $destFolder = Join-Path $DestRoot $folderName

        Write-Info "[$count/$($SelectedDrivers.Count)] $($drv.InfOriginal) - $($drv.Provider) ($($drv.ClassName))"

        if ($IsDryRun) {
            Write-Warn "  [DryRun] pnputil /export-driver $($drv.InfOriginal) '$destFolder'"
            Write-DrvLog -Message "[DryRun] export-driver $($drv.InfOriginal) -> $folderName"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Folder  = $folderName
                Status  = 'DryRun'
                Message = 'Simulado.'
            })
            continue
        }

        New-Item -Path $destFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

        $result = Invoke-ExternalCommand -FilePath 'pnputil.exe' -ArgumentList @('/export-driver', $drv.InfOriginal, $destFolder)

        if ($result.ExitCode -eq 0) {
            Write-Ok "  Exportado: $folderName"
            Write-DrvLog -Message "Backup OK: $($drv.InfOriginal) -> $folderName"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Folder  = $folderName
                Status  = 'OK'
                Message = $result.Output
            })
        }
        else {
            Write-Warn "  Falha (ExitCode $($result.ExitCode)): $($result.Output)"
            Write-DrvLog -Level 'WARN' -Message "Backup FALHOU: $($drv.InfOriginal). $($result.Output)"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Folder  = $folderName
                Status  = 'Falha'
                Message = $result.Output
            })
        }
    }

    return @($results)
}

function Save-DriverMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Results,

        [Parameter(Mandatory = $true)]
        [string]$DestRoot,

        [Parameter(Mandatory = $true)]
        [string]$BackupDate
    )

    $meta = @(
        $Results | Where-Object { $_.Status -eq 'OK' -or $_.Status -eq 'DryRun' } | ForEach-Object {
            [pscustomobject]@{
                InfOriginal      = $_.Driver.InfOriginal
                OriginalFileName = $_.Driver.OriginalFileName
                Provider         = $_.Driver.Provider
                ClassName        = $_.Driver.ClassName
                Version          = $_.Driver.Version
                Date             = $_.Driver.Date
                DeviceNames      = @($_.Driver.DeviceNames)
                HardwareIds      = @($_.Driver.HardwareIds)
                BackupFolder     = $_.Folder
                BackupDate       = $BackupDate
            }
        }
    )

    $metaPath = Join-Path $DestRoot 'metadados.json'
    $json     = $meta | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($metaPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-DrvLog -Message "Metadados salvos: $metaPath"
    return $metaPath
}

# ─── restore ──────────────────────────────────────────────────────────────────

function Invoke-DriverRestore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$SelectedDrivers,

        [Parameter(Mandatory = $true)]
        [string]$BackupSessionPath,

        [bool]$IsDryRun = $false
    )

    $results = [System.Collections.ArrayList]::new()
    $count   = 0

    foreach ($drv in $SelectedDrivers) {
        $count++
        $driverFolder = Join-Path $BackupSessionPath $drv.BackupFolder

        Write-Info "[$count/$($SelectedDrivers.Count)] $($drv.InfOriginal) - $($drv.Provider) ($($drv.ClassName))"

        if (-not $drv.HardwarePresent) {
            $deviceLabel = if ($drv.DeviceNames -and $drv.DeviceNames.Count -gt 0) { $drv.DeviceNames[0] } else { $drv.ClassName }
            Write-Host ''
            Write-Host '  [AVISO] Hardware nao detectado para este driver:' -ForegroundColor Yellow
            Write-Host ("    Driver  : {0} ({1})" -f $deviceLabel, $drv.ClassName) -ForegroundColor Yellow
            Write-Host ("    Provider: {0} | Versao: {1}" -f $drv.Provider, $drv.Version) -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  Instalar um driver sem hardware presente pode causar instabilidade no sistema.' -ForegroundColor Yellow
            Write-Host ''

            $confirm = Read-YesNo -Question '  Deseja instalar mesmo assim?' -DefaultYes $false

            if (-not $confirm) {
                Write-Info "  Ignorado pelo operador: $($drv.InfOriginal)"
                Write-DrvLog -Level 'WARN' -Message "Restore ignorado (hardware ausente, operador recusou): $($drv.InfOriginal)"
                $null = $results.Add([pscustomobject]@{
                    Driver  = $drv
                    Status  = 'Ignorado'
                    Message = 'Hardware ausente; operador recusou instalacao.'
                })
                continue
            }
            Write-DrvLog -Level 'WARN' -Message "Operador confirmou install com hardware ausente: $($drv.InfOriginal)"
        }

        if (-not (Test-Path -LiteralPath $driverFolder)) {
            Write-Warn "  Pasta de backup nao encontrada: $driverFolder"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = 'Falha'
                Message = "Pasta de backup nao encontrada: $driverFolder"
            })
            continue
        }

        $infFiles = @(Get-ChildItem -Path $driverFolder -Filter '*.inf' -ErrorAction SilentlyContinue)
        if ($infFiles.Count -eq 0) {
            Write-Warn "  Arquivo .inf nao encontrado em: $driverFolder"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = 'Falha'
                Message = '.inf nao localizado na pasta de backup.'
            })
            continue
        }

        $infPath = $infFiles[0].FullName

        if ($IsDryRun) {
            Write-Warn "  [DryRun] pnputil /add-driver '$infPath' /install"
            Write-DrvLog -Message "[DryRun] add-driver $infPath"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = 'DryRun'
                Message = 'Simulado.'
            })
            continue
        }

        $result = Invoke-ExternalCommand -FilePath 'pnputil.exe' -ArgumentList @('/add-driver', $infPath, '/install')

        if ($result.ExitCode -eq 0 -or $result.ExitCode -eq 3010) {
            Write-Ok "  Instalado: $($drv.InfOriginal)"
            Write-DrvLog -Message "Restore OK: $($drv.InfOriginal)"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = 'OK'
                Message = $result.Output
            })
        }
        else {
            Write-Warn "  Falha (ExitCode $($result.ExitCode)): $($result.Output)"
            Write-DrvLog -Level 'WARN' -Message "Restore FALHOU: $($drv.InfOriginal). $($result.Output)"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = 'Falha'
                Message = $result.Output
            })
        }
    }

    return @($results)
}

# ─── relatorios ───────────────────────────────────────────────────────────────

function New-DrvTextReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$OutPath
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'

    $sep = '=' * 80
    $lines.Add($sep)
    $lines.Add('  WBA Windows Toolkit - Backup e Restauracao de Drivers')
    $lines.Add("  Versao : $ScriptVersion")
    $lines.Add("  Data   : $($Snapshot.StartedAt)")
    $lines.Add("  Modo   : $($Snapshot.Modo)")
    $lines.Add("  DryRun : $($Snapshot.DryRun)")
    $lines.Add("  Host   : $($Snapshot.ComputerName)")
    $lines.Add($sep)
    $lines.Add('')

    if ($Snapshot.Modo -eq 'Backup') {
        $lines.Add("BACKUP — $($Snapshot.SelectedCount) de $($Snapshot.TotalFound) drivers exportados")
        $lines.Add("Pasta  : $($Snapshot.BackupPath)")
    }
    else {
        $lines.Add("RESTORE — $($Snapshot.SelectedCount) de $($Snapshot.TotalFound) drivers processados")
        $lines.Add("Backup : $($Snapshot.BackupPath)")
    }

    $lines.Add('')
    $lines.Add('RESULTADOS:')
    $hdr = '  {0,-12} {1,-12} {2,-19} {3,-14} {4}' -f 'Status', 'Classe', 'Provider', 'Versao', 'Dispositivo'
    $lines.Add($hdr)
    $lines.Add(('  ' + ('-' * 76)))

    foreach ($r in $Snapshot.Results) {
        $device = if ($r.Driver.DeviceNames -and $r.Driver.DeviceNames.Count -gt 0) { $r.Driver.DeviceNames[0] } else { '-' }
        $lines.Add(('  {0,-12} {1,-12} {2,-19} {3,-14} {4}' -f
            $r.Status, $r.Driver.ClassName, $r.Driver.Provider, $r.Driver.Version, $device))
    }

    $lines.Add('')
    $lines.Add($sep)

    [System.IO.File]::WriteAllLines(
        $OutPath,
        $lines.ToArray(),
        [System.Text.UTF8Encoding]::new($true)
    )

    return $OutPath
}

function New-DrvHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$OutPath
    )

    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in $Snapshot.Results) {
        $device = if ($r.Driver.DeviceNames -and $r.Driver.DeviceNames.Count -gt 0) {
            ConvertTo-HtmlSafe -Value $r.Driver.DeviceNames[0]
        } else { '-' }

        $rowClass = switch ($r.Status) {
            'OK'      { 'ok' }
            'Falha'   { 'fail' }
            'DryRun'  { 'dryrun' }
            default   { 'ignored' }
        }

        $null = $sb.AppendLine(
            '<tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td></tr>' -f
            $rowClass,
            (ConvertTo-HtmlSafe -Value $r.Status),
            (ConvertTo-HtmlSafe -Value $r.Driver.ClassName),
            (ConvertTo-HtmlSafe -Value $r.Driver.Provider),
            (ConvertTo-HtmlSafe -Value $r.Driver.Version),
            (ConvertTo-HtmlSafe -Value $r.Driver.Date),
            $device,
            (ConvertTo-HtmlSafe -Value $r.Driver.InfOriginal)
        )
    }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>WBA - Backup de Drivers</title>
<style>
body { font-family: Arial, sans-serif; font-size: 13px; margin: 20px; color: #222; }
h1 { color: #005a9e; border-bottom: 2px solid #005a9e; padding-bottom: 4px; }
.meta { background: #f0f4f8; padding: 12px 16px; border-radius: 4px; margin-bottom: 16px; font-size: 12px; }
table { border-collapse: collapse; width: 100%; margin-top: 12px; }
th { background: #005a9e; color: #fff; padding: 7px 10px; text-align: left; font-size: 12px; }
td { padding: 5px 10px; border-bottom: 1px solid #ddd; font-size: 12px; }
tr.ok td { background: #e8f5e9; }
tr.fail td { background: #ffebee; }
tr.dryrun td { background: #fff9c4; }
tr.ignored td { background: #f5f5f5; color: #888; }
@media print { body { margin: 0; } .meta { page-break-inside: avoid; } }
</style>
</head>
<body>
<h1>WBA Windows Toolkit — Backup e Restauracao de Drivers</h1>
<div class="meta">
  <b>Modo:</b> $($Snapshot.Modo) &nbsp;&nbsp;
  <b>Data:</b> $($Snapshot.StartedAt) &nbsp;&nbsp;
  <b>Host:</b> $($Snapshot.ComputerName) &nbsp;&nbsp;
  <b>DryRun:</b> $($Snapshot.DryRun) &nbsp;&nbsp;
  <b>Selecionados:</b> $($Snapshot.SelectedCount) de $($Snapshot.TotalFound)
</div>
<table>
<tr><th>Status</th><th>Classe</th><th>Provider</th><th>Versao</th><th>Data</th><th>Dispositivo</th><th>INF</th></tr>
$($sb.ToString())
</table>
</body>
</html>
"@

    [System.IO.File]::WriteAllText(
        $OutPath,
        $html,
        [System.Text.UTF8Encoding]::new($true)
    )

    return $OutPath
}

# ─── execucao principal ───────────────────────────────────────────────────────

Write-Title "WBA Windows Toolkit - Backup e Restauracao de Drivers $ScriptVersion"

if ($DryRun) { Write-Warn 'MODO DRY-RUN: nenhuma alteracao sera realizada no sistema.' }

if (-not (Test-IsAdministrator)) {
    Write-Warn 'Elevando para Administrador (necessario para Get-WindowsDriver e pnputil)...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Modo -ne 'Backup') { $argList += @('-Modo', $Modo) }
    if ($DryRun)    { $argList += '-DryRun' }
    if ($GerarHtml) { $argList += '-GerarHtml' }
    if (-not [string]::IsNullOrEmpty($Path)) { $argList += @('-Path', "`"$Path`"") }
    Start-Process 'powershell.exe' -ArgumentList $argList -Verb RunAs
    return
}

$script:Session = Initialize-ToolkitReportSession -ModuleName 'WbaToolkit.Maintenance' -ReportsRoot $Path
$script:LogPath = Join-Path $script:Session.LogsPath 'drivers.log'

$transcriptPath = Join-Path $script:Session.LogsPath 'drivers-transcript.log'
Start-Transcript -Path $transcriptPath -Append -ErrorAction SilentlyContinue | Out-Null

Write-DrvLog -Message "Sessao iniciada. Modo: $Modo. DryRun: $DryRun. Path: $($script:Session.Path)"
Write-Info "Relatorios em: $($script:Session.Path)"

$startTime   = Get-Date
$results     = @()
$totalFound  = 0
$backupPath  = $script:Session.Path

# ─── modo backup ──────────────────────────────────────────────────────────────

if ($Modo -eq 'Backup') {
    Write-DrvSection 'Enumerando drivers de terceiros instalados'

    $allDrivers = @(Get-ThirdPartyDrivers)
    $totalFound = $allDrivers.Count

    if ($totalFound -eq 0) {
        Write-Warn 'Nenhum driver de terceiros encontrado. Verifique se executa como Administrador.'
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        return
    }

    Write-Info "$totalFound driver(s) de terceiros encontrado(s)."
    Write-Host ''
    Write-Host "Drivers de terceiros instalados ($totalFound):" -ForegroundColor White

    Show-DriverList -Drivers $allDrivers -ShowStatus $false

    $selected = @(Read-DriverSelection -Drivers $allDrivers -ActionLabel 'backup')

    if ($selected.Count -eq 0) {
        Write-Info 'Operacao cancelada pelo operador.'
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        return
    }

    Write-DrvSection "Exportando $($selected.Count) driver(s)"

    $driversRoot = Join-Path $script:Session.Path 'drivers'
    New-Item -Path $driversRoot -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $results = @(Invoke-DriverBackup -SelectedDrivers $selected -DestRoot $driversRoot -IsDryRun ([bool]$DryRun))

    Write-DrvSection 'Salvando metadados'
    $metaPath = Save-DriverMetadata -Results $results -DestRoot $script:Session.Path -BackupDate $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    Write-Info "Metadados: $metaPath"

    $backupPath = $script:Session.Path
}

# ─── modo restore ─────────────────────────────────────────────────────────────

else {
    Write-DrvSection 'Localizando sessao de backup'

    $chosenBackup = Find-BackupFolder -ModulePath $script:Session.ModulePath

    if ($null -eq $chosenBackup) {
        Write-Fail 'Nenhuma sessao de backup encontrada. Execute o Modo Backup primeiro.'
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        return
    }

    Write-Info "Backup selecionado: $chosenBackup"
    Write-DrvLog -Message "Backup selecionado: $chosenBackup"

    Write-DrvSection 'Carregando catalogo do backup'

    $allDrivers = @(Get-BackupDriverCatalog -BackupSessionPath $chosenBackup)
    $totalFound = $allDrivers.Count

    if ($totalFound -eq 0) {
        Write-Fail 'Catalogo de backup vazio ou corrompido.'
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        return
    }

    Write-DrvSection 'Verificando presenca de hardware'

    for ($i = 0; $i -lt $allDrivers.Count; $i++) {
        $hwIds  = @($allDrivers[$i].HardwareIds)
        $allDrivers[$i].HardwarePresent = Test-HardwarePresent -HardwareIds $hwIds
        $statusTxt = if ($allDrivers[$i].HardwarePresent) { 'presente' } else { 'AUSENTE' }
        Write-DrvLog -Message "Hardware $statusTxt`: $($allDrivers[$i].InfOriginal)"
    }

    Write-Info "$totalFound driver(s) no backup."
    Write-Host ''
    Write-Host "Drivers encontrados no backup ($totalFound):" -ForegroundColor White

    Show-DriverList -Drivers $allDrivers -ShowStatus $true

    $selected = @(Read-DriverSelection -Drivers $allDrivers -ActionLabel 'restore')

    if ($selected.Count -eq 0) {
        Write-Info 'Operacao cancelada pelo operador.'
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        return
    }

    Write-DrvSection "Restaurando $($selected.Count) driver(s)"

    $results = @(Invoke-DriverRestore -SelectedDrivers $selected -BackupSessionPath $chosenBackup -IsDryRun ([bool]$DryRun))

    $backupPath = $chosenBackup
}

# ─── relatorios finais ────────────────────────────────────────────────────────

Write-DrvSection 'Exportando relatorio'

$snapshot = [pscustomobject]@{
    StartedAt     = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    Modo          = $Modo
    DryRun        = [bool]$DryRun
    ComputerName  = $env:COMPUTERNAME
    TotalFound    = $totalFound
    SelectedCount = $results.Count
    BackupPath    = $backupPath
    Results       = @($results)
}

$txtPath = Join-Path $script:Session.Path 'relatorio-drivers.txt'
New-DrvTextReport -Snapshot $snapshot -OutPath $txtPath | Out-Null
Write-Ok "Relatorio TXT: $txtPath"

if ($GerarHtml) {
    $htmlPath = Join-Path $script:Session.Path 'relatorio-drivers.html'
    New-DrvHtmlReport -Snapshot $snapshot -OutPath $htmlPath | Out-Null
    Write-Ok "Relatorio HTML: $htmlPath"
}

$okCount   = @($results | Where-Object { $_.Status -eq 'OK' }).Count
$failCount = @($results | Where-Object { $_.Status -eq 'Falha' }).Count
$skipCount = @($results | Where-Object { $_.Status -eq 'Ignorado' }).Count

Write-Host ''
Write-Host "Resumo: $okCount OK  |  $failCount falha(s)  |  $skipCount ignorado(s)" -ForegroundColor White

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null

Write-Host ''
Write-Title "Sessao concluida: $($script:Session.Path)"
