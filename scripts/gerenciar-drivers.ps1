#requires -version 5.1
<#
.SYNOPSIS
    Backup e restauracao de drivers de terceiros instalados no Windows.

.DESCRIPTION
    Enumera drivers OEM (nao-inbox) do sistema, permite selecao granular e executa
    exportacao via pnputil. No modo Restore, aceita pasta de sessao ou pacote ZIP
    (com verificacao SHA256 quando houver .sha256sum), instala via DISM (fallback
    pnputil) e pede confirmacao para sobrescrita ou hardware ausente.

.PARAMETER Modo
    Define a operacao:
      Backup  - enumera e exporta drivers instalados (padrao)
      Restore - localiza backup anterior e reinstala drivers selecionados

.PARAMETER DryRun
    Simula operacoes sem executar DISM/pnputil. Exibe o que seria feito.

.PARAMETER GerarHtml
    Gera relatorio HTML alem do TXT.

.PARAMETER Path
    Raiz de relatorios/backup. Quando omitido, usa configuracao do toolkit ou C:\WBA\Relatorios.

.PARAMETER CaminhoBackup
    No modo Restore, caminho para pasta de sessao ou pacote .zip. Quando omitido,
    lista sessoes sob a raiz de relatorios do modulo drivers.

.PARAMETER PacoteBackup
    No modo Backup, cria pacote ZIP (metadados + drivers) com hash SHA256.

.PARAMETER Help
    Exibe a ajuda resumida do script e encerra.

.EXAMPLE
    .\gerenciar-drivers.ps1

.EXAMPLE
    .\gerenciar-drivers.ps1 -DryRun

.EXAMPLE
    .\gerenciar-drivers.ps1 -Modo Restore -GerarHtml

.EXAMPLE
    .\gerenciar-drivers.ps1 -Modo Restore -CaminhoBackup "D:\Backup\drv_pc01-31072026-v01.zip"

.EXAMPLE
    .\gerenciar-drivers.ps1 -Path "D:\Backup\Drivers"

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
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
    [string]$Path,

    [string]$CaminhoBackup,

    [switch]$PacoteBackup,

    [switch]$Help,
    [switch]$Version
)

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

$ScriptVersion = 'v1.1.0'
$ToolkitRoot   = Split-Path -Parent $PSScriptRoot

$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'

if (-not (Test-Path -LiteralPath $coreModuleRoot)) {
    throw "Modulo nao encontrado: $coreModuleRoot"
}

try {
    foreach ($sub in @('Private', 'Public')) {
        $dir = Join-Path $coreModuleRoot $sub
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
        }
    }
}
catch {
    throw "Nao foi possivel carregar WbaToolkit.Core: $($_.Exception.Message)"
}

# WBA-DOCS: Category=Maintenance; Manual=Backup e restauracao de drivers OEM via DISM/pnputil

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
    Write-Section $Title
    Write-DrvLog -Message $Title
}

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Backup e Restauracao de Drivers — $script:ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$script:ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Modo <Backup|Restore>  Operacao a executar. Padrao: Backup."
    Write-Host "  -DryRun            Simula sem executar DISM/pnputil; exibe o que seria feito."
    Write-Host "  -GerarHtml         Gera relatorio HTML alem do TXT."
    Write-Host "  -CaminhoBackup     Pasta de sessao ou .zip para Restore (opcional)."
    Write-Host "  -PacoteBackup      Cria pacote ZIP (metadados+drivers) com hash SHA256."
    Write-Host "  -DiretorioSaida '<dir>' Raiz de relatorios/backup. Padrao: config do toolkit ou C:\WBA\Relatorios"
    Write-Host "  -Help              Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$script:ScriptName"
    Write-Host "  .\$script:ScriptName -DryRun"
    Write-Host "  .\$script:ScriptName -PacoteBackup"
    Write-Host "  .\$script:ScriptName -Modo Restore -GerarHtml"
    Write-Host "  .\$script:ScriptName -Modo Restore -CaminhoBackup 'D:\drv_pc01-v01.zip'"
    Write-Host ""
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
        Write-DrvLog -Level 'WARN' -Message "metadados.json nao encontrado em: $BackupSessionPath; montando catalogo pelas pastas."
        return @(New-DriverCatalogFromFolders -BackupSessionPath $BackupSessionPath)
    }

    $json    = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $catalog = $json | ConvertFrom-Json

    $result = [System.Collections.ArrayList]::new()
    foreach ($item in @($catalog)) {
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
        $rawInput = ([string](Read-Host 'Selecione a sessao de backup [1]')).Trim()
        if ($rawInput -eq '') { return $candidates[0].FullName }

        $num = 0
        if ([int]::TryParse($rawInput, [ref]$num) -and $num -ge 1 -and $num -le $candidates.Count) {
            return $candidates[$num - 1].FullName
        }
        Write-Warn "Numero invalido. Selecione entre 1 e $($candidates.Count)."
    }
}

function Test-DriverBackupHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath
    )

    $hashFile = "$ZipPath.sha256sum"
    if (-not (Test-Path -LiteralPath $hashFile -PathType Leaf)) {
        Write-DrvLog -Message "Arquivo de hash ausente (ok): $hashFile"
        return [pscustomobject]@{
            Verified = $false
            Skipped  = $true
            Expected = $null
            Actual   = $null
            HashFile = $hashFile
        }
    }

    $rawLine = @(Get-Content -LiteralPath $hashFile -Encoding UTF8 | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }) | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($rawLine)) {
        throw "Arquivo de hash vazio: $hashFile"
    }

    $expected = ($rawLine -split '\s+', 2)[0].Trim().ToUpperInvariant()
    if ($expected -notmatch '^[0-9A-F]{64}$') {
        throw "Hash SHA256 invalido em: $hashFile"
    }

    $actual = (Get-FileHashSha256 -Path $ZipPath -Quiet).ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Hash SHA256 nao confere para '$ZipPath'. Esperado=$expected Atual=$actual"
    }

    Write-Ok "Hash SHA256 verificado: $actual"
    Write-DrvLog -Message "Hash SHA256 OK: $actual"

    return [pscustomobject]@{
        Verified = $true
        Skipped  = $false
        Expected = $expected
        Actual   = $actual
        HashFile = $hashFile
    }
}

function Get-DriverFolderCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupSessionPath,
        [Parameter(Mandatory = $true)][string]$BackupFolder
    )

    $paths = @(
        (Join-Path (Join-Path $BackupSessionPath 'drivers') $BackupFolder),
        (Join-Path $BackupSessionPath $BackupFolder)
    )

    return @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Resolve-DriverPackageFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupSessionPath,
        [Parameter(Mandatory = $true)][string]$BackupFolder
    )

    foreach ($candidate in @(Get-DriverFolderCandidates -BackupSessionPath $BackupSessionPath -BackupFolder $BackupFolder)) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }
    }

    return $null
}

function New-DriverCatalogFromFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupSessionPath
    )

    $searchRoots = [System.Collections.ArrayList]::new()
    $driversRoot = Join-Path $BackupSessionPath 'drivers'
    if (Test-Path -LiteralPath $driversRoot -PathType Container) {
        $null = $searchRoots.Add($driversRoot)
    }
    else {
        $null = $searchRoots.Add($BackupSessionPath)
    }

    $result = [System.Collections.ArrayList]::new()
    foreach ($root in $searchRoots) {
        $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)
        foreach ($dir in $dirs) {
            $inf = @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.inf' -File -ErrorAction SilentlyContinue |
                Select-Object -First 1)
            if ($inf.Count -eq 0) { continue }

            $null = $result.Add([pscustomobject]@{
                    InfOriginal      = $inf[0].Name
                    OriginalFileName = $inf[0].Name
                    Provider         = '(desconhecido)'
                    ClassName        = '(desconhecida)'
                    Version          = ''
                    Date             = ''
                    DeviceNames      = @()
                    HardwareIds      = @()
                    BackupFolder     = $dir.Name
                    BackupDate       = ''
                    HardwarePresent  = $false
                })
        }
    }

    return @($result)
}

function Resolve-DriverBackupSource {
    [CmdletBinding()]
    param(
        [string]$CaminhoBackup,
        [Parameter(Mandatory = $true)][string]$ModulePath,
        [Parameter(Mandatory = $true)][string]$ExtractRoot
    )

    if ([string]::IsNullOrWhiteSpace($CaminhoBackup)) {
        $chosen = Find-BackupFolder -ModulePath $ModulePath
        if ($null -eq $chosen) { return $null }
        return [pscustomobject]@{
            SessionPath = $chosen
            SourceKind  = 'Sessao'
            ZipPath     = $null
            HashChecked = $false
        }
    }

    if (-not (Test-Path -LiteralPath $CaminhoBackup)) {
        throw "CaminhoBackup nao encontrado: $CaminhoBackup"
    }

    $item = Get-Item -LiteralPath $CaminhoBackup

    if ($item.PSIsContainer) {
        $sessionPath = $item.FullName
        $metaPath = Join-Path $sessionPath 'metadados.json'
        if (-not (Test-Path -LiteralPath $metaPath) -and
            -not (Test-Path -LiteralPath (Join-Path $sessionPath 'drivers'))) {
            throw "Pasta de backup sem metadados.json nem pasta drivers: $sessionPath"
        }

        return [pscustomobject]@{
            SessionPath = $sessionPath
            SourceKind  = 'Pasta'
            ZipPath     = $null
            HashChecked = $false
        }
    }

    if ($item.Extension -ne '.zip') {
        throw "CaminhoBackup deve ser pasta ou arquivo .zip: $CaminhoBackup"
    }

    $hashResult = Test-DriverBackupHash -ZipPath $item.FullName

    if (Test-Path -LiteralPath $ExtractRoot) {
        Remove-Item -LiteralPath $ExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $ExtractRoot -ItemType Directory -Force | Out-Null

    Write-Info "Extraindo pacote ZIP para: $ExtractRoot"
    Write-DrvLog -Message "Expand-Archive: $($item.FullName) -> $ExtractRoot"
    Expand-Archive -LiteralPath $item.FullName -DestinationPath $ExtractRoot -Force

    $sessionPath = $ExtractRoot
    $metaAtRoot = Join-Path $ExtractRoot 'metadados.json'
    $nestedSessions = @(Get-ChildItem -LiteralPath $ExtractRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'metadados.json') })

    if (-not (Test-Path -LiteralPath $metaAtRoot) -and $nestedSessions.Count -eq 1) {
        $sessionPath = $nestedSessions[0].FullName
    }

    return [pscustomobject]@{
        SessionPath = $sessionPath
        SourceKind  = 'Zip'
        ZipPath     = $item.FullName
        HashChecked = [bool]$hashResult.Verified
    }
}

function Test-DriverAlreadyInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InfOriginal,
        [string]$OriginalFileName
    )

    try {
        $installed = @(Get-WindowsDriver -Online -All -ErrorAction Stop)
    }
    catch {
        Write-DrvLog -Level 'WARN' -Message "Nao foi possivel consultar drivers instalados: $($_.Exception.Message)"
        return $false
    }

    foreach ($drv in $installed) {
        if ($InfOriginal -and ($drv.Driver -eq $InfOriginal)) { return $true }
        if ($OriginalFileName -and ($drv.OriginalFileName -like "*$OriginalFileName")) { return $true }
    }

    return $false
}

function Install-DriverPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DriverFolder,
        [Parameter(Mandatory = $true)][string]$InfPath,
        [bool]$IsDryRun = $false
    )

    if ($IsDryRun) {
        Write-Warn "  [DryRun] dism /Online /Add-Driver /Driver:'$DriverFolder' /Recurse"
        Write-DrvLog -Message "[DryRun] Add-Driver $DriverFolder"
        return [pscustomobject]@{
            Status  = 'DryRun'
            Backend = 'DISM'
            Message = 'Simulado.'
            ExitCode = 0
        }
    }

    $dismArgs = @('/Online', '/Add-Driver', "/Driver:$DriverFolder", '/Recurse')
    Write-DrvLog -Message "DISM $($dismArgs -join ' ')"
    $dismResult = Invoke-ExternalCommand -FilePath 'dism.exe' -ArgumentList $dismArgs

    if ($dismResult.ExitCode -eq 0 -or $dismResult.ExitCode -eq 3010) {
        return [pscustomobject]@{
            Status   = 'OK'
            Backend  = 'DISM'
            Message  = $dismResult.Output
            ExitCode = $dismResult.ExitCode
        }
    }

    Write-Warn "  DISM falhou (ExitCode $($dismResult.ExitCode)); tentando pnputil..."
    Write-DrvLog -Level 'WARN' -Message "DISM falhou: $($dismResult.Output). Fallback pnputil."

    $pnpResult = Invoke-ExternalCommand -FilePath 'pnputil.exe' -ArgumentList @('/add-driver', $InfPath, '/install')
    if ($pnpResult.ExitCode -eq 0 -or $pnpResult.ExitCode -eq 3010) {
        return [pscustomobject]@{
            Status   = 'OK'
            Backend  = 'pnputil'
            Message  = $pnpResult.Output
            ExitCode = $pnpResult.ExitCode
        }
    }

    return [pscustomobject]@{
        Status   = 'Falha'
        Backend  = 'DISM+pnputil'
        Message  = "DISM: $($dismResult.Output) | pnputil: $($pnpResult.Output)"
        ExitCode = $pnpResult.ExitCode
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
    Write-Host '  [numeros]  ex: 1,3,5   ou  1,7,18-20   Selecionar individualmente' -ForegroundColor Gray
    Write-Host '  [T]                    Todos' -ForegroundColor Gray
    Write-Host '  [N]                    Cancelar' -ForegroundColor Gray
    Write-Host ''

    while ($true) {
        $rawInput = ([string](Read-Host 'Selecao')).Trim()
        if ($rawInput -eq '') { continue }
        if ($rawInput -ieq 'N') { return @() }
        if ($rawInput -ieq 'T') { return $Drivers }

        $parts    = $rawInput -split '[,\s]+'
        $selected = [System.Collections.ArrayList]::new()
        $valid    = $true

        foreach ($part in $parts) {
            $part = $part.Trim()
            if ($part -eq '') { continue }

            # Suportar intervalos: 18-20 expande para 18,19,20
            if ($part -match '^(\d+)-(\d+)$') {
                $rangeStart = [int]$Matches[1]
                $rangeEnd   = [int]$Matches[2]

                if ($rangeStart -gt $rangeEnd) {
                    Write-Warn "Intervalo invalido: $part (inicio > fim)."
                    $valid = $false
                    break
                }
                if ($rangeStart -lt 1 -or $rangeEnd -gt $Drivers.Count) {
                    Write-Warn "Intervalo fora do alcance: $part (1 a $($Drivers.Count))."
                    $valid = $false
                    break
                }

                for ($i = $rangeStart; $i -le $rangeEnd; $i++) {
                    $null = $selected.Add($Drivers[$i - 1])
                }
            }
            else {
                # Numero individual
                $num = 0
                if (-not [int]::TryParse($part, [ref]$num)) {
                    Write-Warn "Entrada invalida: '$part'. Use numeros, intervalos (ex: 18-20), T ou N."
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
        }

        if ($valid -and $selected.Count -gt 0) { return @($selected) }
        if ($valid -and $selected.Count -eq 0) { Write-Warn 'Nenhum driver selecionado. Digite numeros, intervalos, T ou N.' }
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
        $driverFolder = Resolve-DriverPackageFolder -BackupSessionPath $BackupSessionPath -BackupFolder $drv.BackupFolder

        Write-Info "[$count/$($SelectedDrivers.Count)] $($drv.InfOriginal) - $($drv.Provider) ($($drv.ClassName))"

        if (-not $drv.HardwarePresent) {
            $deviceLabel = if ($drv.DeviceNames -and $drv.DeviceNames.Count -gt 0) { $drv.DeviceNames[0] } else { $drv.ClassName }
            Write-Host ''
                Write-Warn 'Hardware nao detectado para este driver:'
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

        if ([string]::IsNullOrWhiteSpace($driverFolder)) {
            $tried = @(Get-DriverFolderCandidates -BackupSessionPath $BackupSessionPath -BackupFolder $drv.BackupFolder) -join '; '
            Write-Warn "  Pasta de backup nao encontrada para '$($drv.BackupFolder)' (tentativas: $tried)"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = 'Falha'
                Message = "Pasta de backup nao encontrada: $($drv.BackupFolder)"
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

        $alreadyInstalled = Test-DriverAlreadyInstalled -InfOriginal $drv.InfOriginal -OriginalFileName $drv.OriginalFileName
        if ($alreadyInstalled) {
            Write-Host ''
            Write-Warn "Driver ja presente no sistema (possivel sobrescrita): $($drv.InfOriginal)"
            Write-Host ("    Provider: {0} | Versao backup: {1}" -f $drv.Provider, $drv.Version) -ForegroundColor Yellow
            Write-Host ''
            $overwrite = Read-YesNo -Question '  Confirma sobrescrita/reinstalacao deste driver?' -DefaultYes $false
            if (-not $overwrite) {
                Write-Info "  Sobrescrita recusada: $($drv.InfOriginal)"
                Write-DrvLog -Level 'WARN' -Message "Restore ignorado (sobrescrita recusada): $($drv.InfOriginal)"
                $null = $results.Add([pscustomobject]@{
                    Driver  = $drv
                    Status  = 'Ignorado'
                    Message = 'Operador recusou sobrescrita de driver ja instalado.'
                })
                continue
            }
            Write-DrvLog -Message "Operador confirmou sobrescrita: $($drv.InfOriginal)"
        }

        $install = Install-DriverPackage -DriverFolder $driverFolder -InfPath $infPath -IsDryRun $IsDryRun

        if ($install.Status -eq 'OK' -or $install.Status -eq 'DryRun') {
            $label = if ($install.Status -eq 'DryRun') { 'Simulado' } else { "Instalado via $($install.Backend)" }
            Write-Ok "  ${label}: $($drv.InfOriginal)"
            Write-DrvLog -Message "Restore $($install.Status) [$($install.Backend)]: $($drv.InfOriginal)"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = $install.Status
                Message = $install.Message
            })
        }
        else {
            Write-Warn "  Falha (ExitCode $($install.ExitCode)): $($install.Message)"
            Write-DrvLog -Level 'WARN' -Message "Restore FALHOU: $($drv.InfOriginal). $($install.Message)"
            $null = $results.Add([pscustomobject]@{
                Driver  = $drv
                Status  = 'Falha'
                Message = $install.Message
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
        if ($Snapshot.ZipPath) {
            $lines.Add("Pacote : $($Snapshot.ZipPath)")
            $lines.Add("Hash   : $($Snapshot.ZipHash)")
        }
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

    # Status das linhas da tabela
    $rowHtml = foreach ($r in $Snapshot.Results) {
        $device = if ($r.Driver.DeviceNames -and $r.Driver.DeviceNames.Count -gt 0) {
            ConvertTo-HtmlSafe -Value $r.Driver.DeviceNames[0]
        } else { '-' }

        $badgeClass = switch ($r.Status) {
            'OK'      { 'badge-green' }
            'Falha'   { 'badge-red' }
            'DryRun'  { 'badge-yellow' }
            default   { 'badge-gray' }
        }

        '<tr><td><span class="badge {0}">{1}</span></td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td class="mono">{6}</td><td class="mono">{7}</td></tr>' -f
            $badgeClass,
            (ConvertTo-HtmlSafe -Value $r.Status),
            (ConvertTo-HtmlSafe -Value $r.Driver.ClassName),
            (ConvertTo-HtmlSafe -Value $r.Driver.Provider),
            (ConvertTo-HtmlSafe -Value $r.Driver.Version),
            (ConvertTo-HtmlSafe -Value $r.Driver.Date),
            $device,
            (ConvertTo-HtmlSafe -Value $r.Driver.InfOriginal)
    }

    # Resumo para cards
    $okCount     = @($Snapshot.Results | Where-Object { $_.Status -eq 'OK' }).Count
    $failCount   = @($Snapshot.Results | Where-Object { $_.Status -eq 'Falha' }).Count
    $dryrunCount = @($Snapshot.Results | Where-Object { $_.Status -eq 'DryRun' }).Count

    # Montar corpo HTML
    $bodyHtml = @"
  <div class="cards">
    <div class="card">
      <div class="card-icon">&#128187;</div>
      <div class="card-label">Computador</div>
      <div class="card-value">$($Snapshot.ComputerName)</div>
      <div class="card-sub">Host de origem</div>
    </div>
    <div class="card" style="border-left-color:var(--accent)">
      <div class="card-icon">&#128230;</div>
      <div class="card-label">Total Encontrados</div>
      <div class="card-value">$($Snapshot.TotalFound)</div>
      <div class="card-sub">drivers no sistema</div>
    </div>
    <div class="card card-ok">
      <div class="card-icon">&#9989;</div>
      <div class="card-label">OK</div>
      <div class="card-value" style="color:var(--success)">$okCount</div>
      <div class="card-sub">copiados com sucesso</div>
    </div>
    <div class="card card-danger">
      <div class="card-icon">&#10060;</div>
      <div class="card-label">Falhas</div>
      <div class="card-value" style="color:var(--danger)">$failCount</div>
      <div class="card-sub">erros na copia</div>
    </div>
    <div class="card" style="border-left-color:var(--warning)">
      <div class="card-icon">&#128260;</div>
      <div class="card-label">DryRun</div>
      <div class="card-value" style="color:var(--warning)">$dryrunCount</div>
      <div class="card-sub">simulados</div>
    </div>
  </div>
  <div class="section">
    <div class="section-hdr">&#128187; Detalhes da Operacao</div>
    <div class="section-body">
      <table class="kv-table">
        <tr><th>Modo</th><td>$($Snapshot.Modo)</td></tr>
        <tr><th>Data/Hora</th><td>$($Snapshot.StartedAt)</td></tr>
        <tr><th>Host</th><td>$($Snapshot.ComputerName)</td></tr>
        <tr><th>DryRun</th><td>$($Snapshot.DryRun)</td></tr>
        <tr><th>Selecionados</th><td>$($Snapshot.SelectedCount) de $($Snapshot.TotalFound)</td></tr>
      </table>
    </div>
  </div>
  <div class="section">
    <div class="section-hdr">&#128203; Drivers Processados</div>
    <div class="section-body">
      <div style="overflow-x:auto">
      <table class="data-table">
        <thead><tr><th>Status</th><th>Classe</th><th>Provider</th><th>Versao</th><th>Data</th><th>Dispositivo</th><th>INF</th></tr></thead>
        <tbody>$($rowHtml -join "`n")</tbody>
      </table>
      </div>
    </div>
  </div>
  <div class="section">
    <div class="section-hdr">&#128193; Localizacao do Backup</div>
    <div class="section-body">
      <table class="kv-table">
        <tr><th>Arquivos soltos</th><td class="mono">$($Snapshot.BackupPath)</td></tr>
        $(if ($Snapshot.ZipPath) {
        "<tr><th>Pacote ZIP</th><td class='mono'>$($Snapshot.ZipPath)</td></tr>"
        "<tr><th>Hash SHA256</th><td class='mono'>$($Snapshot.ZipHash)</td></tr>"
        })
      </table>
    </div>
  </div>
"@

    # Gerar HTML usando template padronizado
    $html = New-ToolkitHtmlReport -Title "Backup e Restauracao de Drivers" `
        -Subtitle "$($Snapshot.Modo) — $($Snapshot.ComputerName)" `
        -Icon "&#128187;" `
        -MetaRight @(
            "Modo: $($Snapshot.Modo)",
            "Data: $($Snapshot.StartedAt)",
            "Host: $($Snapshot.ComputerName)",
            "DryRun: $($Snapshot.DryRun)",
            "Selecionados: $($Snapshot.SelectedCount) de $($Snapshot.TotalFound)"
        ) `
        -Body $bodyHtml `
        -FooterText "Gerado por WBA Windows Toolkit em $($Snapshot.StartedAt)"

    [System.IO.File]::WriteAllText(
        $OutPath,
        $html,
        [System.Text.UTF8Encoding]::new($true)
    )

    return $OutPath
}

# ─── execucao principal ───────────────────────────────────────────────────────

if ($Help) { Show-Help; exit 0 }
if ($Version) { Write-Host "Script: $ScriptName — $ScriptVersion" -ForegroundColor Green; exit 0 }

Write-Title "WBA Windows Toolkit - Backup e Restauracao de Drivers $ScriptVersion"

if ($DryRun) { Write-Warn 'MODO DRY-RUN: nenhuma alteracao sera realizada no sistema.' }

if (-not (Test-IsAdministrator)) {
    Write-Warn 'Elevando para Administrador (necessario para Get-WindowsDriver e DISM/pnputil)...'
    $cmd = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) -Verb RunAs
    return
}

$script:Session = Initialize-ToolkitReportSession -ModuleName 'drivers' -ReportsRoot $Path -CreateBackups
$script:LogPath = Join-Path $script:Session.LogsPath 'drivers.log'

$transcriptPath = Join-Path $script:Session.LogsPath 'drivers-transcript.log'
Start-Transcript -Path $transcriptPath -Append -ErrorAction SilentlyContinue | Out-Null

Write-DrvLog -Message "Sessao iniciada. Modo: $Modo. DryRun: $DryRun. Path: $($script:Session.Path)"
Write-Info "Relatorios em: $($script:Session.Path)"

$startTime   = Get-Date
$results     = @()
$totalFound  = 0
$backupPath  = $script:Session.Path
$zipPath     = $null
$zipHash     = $null

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

    # ─── Empacotamento ZIP + SHA256 ──────────────────────────────────────────
    if ($PacoteBackup -and -not $DryRun) {
        Write-DrvSection 'Empacotando backup em ZIP'

        # Gerar nome do pacote: drv_hostname-ddmmyyyy-vxx.zip
        $hostname  = $env:COMPUTERNAME.ToLower()
        $dateStr   = Get-Date -Format 'ddMMyyyy'
        $baseName  = "drv_$hostname-$dateStr"

        # Determinar versao (v01, v02, ...)
        $archiveVersion = 1
        $reportsRoot = if (-not [string]::IsNullOrEmpty($Path)) { $Path } else { Get-ToolkitReportsRoot }
        $existingPackages = Get-ChildItem -Path $reportsRoot -Filter "$baseName-v*.zip" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1

        if ($existingPackages) {
            if ($existingPackages.Name -match 'v(\d+)\.zip$') {
                $archiveVersion = [int]$Matches[1] + 1
            }
        }

        $versionStr = "v{0:D2}" -f $archiveVersion
        $zipName    = "$baseName-$versionStr.zip"
        $zipPath    = Join-Path $reportsRoot $zipName

        # Staging com metadados.json + drivers/ para o restore localizar o catalogo
        $packageStage = Join-Path $script:Session.Path 'package-stage'
        if (Test-Path -LiteralPath $packageStage) {
            Remove-Item -LiteralPath $packageStage -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $packageStage -ItemType Directory -Force | Out-Null

        if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
            Copy-Item -LiteralPath $metaPath -Destination (Join-Path $packageStage 'metadados.json') -Force
        }
        if (Test-Path -LiteralPath $driversRoot -PathType Container) {
            Copy-Item -LiteralPath $driversRoot -Destination (Join-Path $packageStage 'drivers') -Recurse -Force
        }

        # Criar pacote ZIP com hash
        $archiveResult = New-ToolkitArchive -SourcePath $packageStage -DestinationPath $zipPath -GenerateHash

        $zipPath = $archiveResult.ZipPath
        $zipHash = $archiveResult.Hash

        Write-Ok "Pacote ZIP: $($archiveResult.ZipPath) ($($archiveResult.ZipSize) KB)"
        Write-Ok "Hash SHA256: $($archiveResult.Hash)"
        Write-DrvLog -Message "Pacote ZIP criado: $($archiveResult.ZipPath) | Hash: $($archiveResult.Hash)"
    }
}

# ─── modo restore ─────────────────────────────────────────────────────────────

else {
    Write-DrvSection 'Localizando fonte de backup'

    $extractRoot = Join-Path $script:Session.Path 'restore-extract'
    try {
        $backupSource = Resolve-DriverBackupSource -CaminhoBackup $CaminhoBackup -ModulePath $script:Session.ModulePath -ExtractRoot $extractRoot
    }
    catch {
        Write-Fail $_.Exception.Message
        Write-DrvLog -Level 'ERROR' -Message $_.Exception.Message
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        return
    }

    if ($null -eq $backupSource) {
        Write-Fail 'Nenhuma sessao de backup encontrada. Informe -CaminhoBackup ou execute o Modo Backup primeiro.'
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        return
    }

    $chosenBackup = $backupSource.SessionPath
    Write-Info "Fonte: $($backupSource.SourceKind) -> $chosenBackup"
    if ($backupSource.ZipPath) {
        Write-Info "Pacote ZIP: $($backupSource.ZipPath)"
        if ($backupSource.HashChecked) {
            Write-Info 'Integridade SHA256 validada.'
        }
        else {
            Write-Warn 'Pacote ZIP sem .sha256sum — integridade nao verificada.'
        }
    }
    Write-DrvLog -Message "Backup selecionado ($($backupSource.SourceKind)): $chosenBackup"

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
    if ($backupSource.ZipPath) {
        $zipPath = $backupSource.ZipPath
    }
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
    ZipPath       = $zipPath
    ZipHash       = $zipHash
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
