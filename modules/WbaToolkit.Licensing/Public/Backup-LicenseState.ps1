function Backup-LicenseState {
    <#
    .SYNOPSIS
        Salva snapshot completo do estado de licenciamento antes de operacoes de escrita.

    .DESCRIPTION
        Coleta product key parcial, canal, status, HWID, dados slmgr e hardware context,
        e salva como JSON com timestamp. Util como backup pre-operacional para permitir
        auditoria e rollback documentado apos alteracoes de licenciamento.

    .PARAMETER Path
        Diretorio onde o snapshot sera salvo. Se omitido, usa ReportsRoot persistente
        ou C:\WBA\Relatorios\licenciamento\backups\<timestamp>\.

    .OUTPUTS
        PSCustomObject com propriedades: BackupPath, Snapshot (objeto completo), Success.

    .EXAMPLE
        $backup = Backup-LicenseState
        # Salva em C:\WBA\Relatorios\licenciamento\backups\20260730_102500\

    .EXAMPLE
        $backup = Backup-LicenseState -Path 'C:\Temp\backups'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $coreLoaded = Get-Module -Name WbaToolkit.Core -ErrorAction SilentlyContinue
        if ($coreLoaded) {
            $session = Initialize-ToolkitReportSession -ModuleName 'licenciamento'
            $backupDir = Join-Path $session.Path "backups\$timestamp"
        }
        else {
            $backupDir = Join-Path "C:\WBA\Relatorios\licenciamento\backups" $timestamp
        }
    }
    else {
        $backupDir = Join-Path $Path "licenciamento-backup-$timestamp"
    }

    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $product = Get-SoftwareLicensingProduct | Where-Object {
        $_.LicenseStatus -ne $null -and $_.LicenseStatus -gt 0
    } | Select-Object -First 1

    $service = Get-SoftwareLicensingService | Select-Object -First 1

    $rawDli = Invoke-Slmgr -ArgumentList '/dli'
    $rawDlv = Invoke-Slmgr -ArgumentList '/dlv'
    $rawXpr = Invoke-Slmgr -ArgumentList '/xpr'

    $licenseInfo = $null
    if ($product) {
        $licenseInfo = ConvertTo-LicenseInfoObject `
            -Product $product `
            -Service $service `
            -SlmgrDli $rawDli `
            -SlmgrDlv $rawDlv `
            -SlmgrXpr $rawXpr
    }

    $hardware = Get-LicenseHardwareContext

    $oemKey = Get-OemProductKey

    $cycleStatus = $null
    if (Get-Command -Name Get-LicenseCycleStatus -ErrorAction SilentlyContinue) {
        $cycleStatus = Get-LicenseCycleStatus
    }

    $snapshot = [pscustomobject]@{
        BackupTimestamp = (Get-Date).ToString('o')
        ComputerName   = $env:COMPUTERNAME
        Product        = if ($product) {
            [pscustomobject]@{
                Name             = [string]$product.Name
                Description      = [string]$product.Description
                LicenseStatus    = [int]$product.LicenseStatus
                PartialProductKey = [string]$product.PartialProductKey
                ProductId        = [string]$product.ID
                ApplicationId    = [string]$product.ApplicationId
                InstallationID   = [string]$product.InstallationID
                Version          = [string]$product.Version
            }
        } else { $null }
        Service        = if ($service) {
            [pscustomobject]@{
                KeyManagementServiceMachine = [string]$service.KeyManagementServiceMachine
                KeyManagementServicePort    = [string]$service.KeyManagementServicePort
                RemainingWindowsReArmCount  = [int]$service.RemainingWindowsReArmCount
            }
        } else { $null }
        LicenseInfo    = $licenseInfo
        Hardware       = $hardware
        OemKey         = $oemKey
        CycleStatus    = if ($cycleStatus) {
            [pscustomobject]@{
                State          = $cycleStatus.State
                StateCode      = $cycleStatus.StateCode
                DaysRemaining  = $cycleStatus.DaysRemaining
                ExpirationDate = $cycleStatus.ExpirationDate
                Channel        = $cycleStatus.Channel
            }
        } else { $null }
        SlmgrOutput    = [pscustomobject]@{
            Dli = if ($rawDli -and $rawDli.Lines) { $rawDli.Lines -join "`n" } else { '' }
            Dlv = if ($rawDlv -and $rawDlv.Lines) { $rawDlv.Lines -join "`n" } else { '' }
            Xpr = if ($rawXpr -and $rawXpr.Lines) { $rawXpr.Lines -join "`n" } else { '' }
        }
    }

    $jsonPath = Join-Path $backupDir 'license-backup.json'
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $readmePath = Join-Path $backupDir 'README.txt'
    $readme = @()
    $readme += "WBA Windows Toolkit — Backup de Licenciamento"
    $readme += "Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $readme += "Computador: $env:COMPUTERNAME"
    $readme += ""
    $readme += "Arquivo de snapshot: license-backup.json"
    $readme += "Para restaurar/consultar: deserialize o JSON."
    $readme += ""
    if ($product) {
        $readme += "Estado: $($licenseInfo.Licenca.Status) | Canal: $($licenseInfo.Licenca.Canal)"
        $readme += "Partial Key: $($licenseInfo.Licenca.PartialProductKey)"
    }
    $readme -join "`r`n" | Set-Content -LiteralPath $readmePath -Encoding UTF8

    [pscustomobject]@{
        BackupPath = $backupDir
        JsonPath   = $jsonPath
        Snapshot   = $snapshot
        Success    = $true
    }
}
