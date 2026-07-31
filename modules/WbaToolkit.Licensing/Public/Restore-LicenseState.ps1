function Restore-LicenseState {
    <#
    .SYNOPSIS
        Restaura configuracao de licenciamento a partir de um snapshot salvo.

    .DESCRIPTION
        Le um backup JSON gerado por Backup-LicenseState e restaura as configuracoes
        que podem ser aplicadas: product key e servidor KMS.

        A funcao NAO restaura: LicenseStatus (ativacao e validada pelo Windows),
        InstallationID (vinculado ao hardware), nem ProductId. Estes valores sao
        preservados apenas para auditoria/comparacao.

        O fluxo e:
        1. Valida o backup (JSON parseavel, campos obrigatorios)
        2. Compara estado atual vs snapshot (mostra diferencas)
        3. Aplica restauracao com -Confirm ou -Force (sem prompt)

    .PARAMETER BackupPath
        Caminho direto para o arquivo license-backup.json OU diretorio contendo o arquivo.

    .PARAMETER AutoDiscover
        Busca automaticamente o backup mais recente na pasta de backups padrao.

    .PARAMETER Force
        Aplica restauracao sem solicitacao de confirmacao.

    .PARAMETER DryRun
        Simula a restauracao sem executar. Mostra o que seria feito.

    .OUTPUTS
        PSCustomObject com propriedades: Success, Restored[], Skipped[], Diffs[], BackupInfo.

    .EXAMPLE
        Restore-LicenseState -BackupPath 'C:\WBA\Relatorios\licenciamento\backups\20260730_102500'

    .EXAMPLE
        Restore-LicenseState -AutoDiscover -DryRun

    .EXAMPLE
        Restore-LicenseState -BackupPath '.\license-backup.json' -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Path')]
        [string]$BackupPath,

        [Parameter(Mandatory = $false, ParameterSetName = 'Auto')]
        [switch]$AutoDiscover,

        [switch]$Force,

        [switch]$DryRun
    )

    $jsonFile = $null

    if ($AutoDiscover) {
        $backupRoot = Join-Path "C:\WBA\Relatorios\licenciamento" 'backups'
        if (Get-Command -Name Get-ToolkitReportsRoot -ErrorAction SilentlyContinue) {
            $root = Get-ToolkitReportsRoot
            if ($root) { $backupRoot = Join-Path $root 'licenciamento\backups' }
        }

        if (Test-Path -LiteralPath $backupRoot -PathType Container) {
            $latest = Get-ChildItem -LiteralPath $backupRoot -Directory |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($latest) {
                $jsonFile = Join-Path $latest.FullName 'license-backup.json'
            }
        }

        if (-not $jsonFile -or -not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) {
            [pscustomobject]@{
                Success    = $false
                Restored   = @()
                Skipped    = @()
                Diffs      = @()
                BackupInfo = $null
                Message    = 'Nenhum backup encontrado na pasta padrao.'
            }
            return
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
        if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
            $jsonFile = $BackupPath
        }
        elseif (Test-Path -LiteralPath $BackupPath -PathType Container) {
            $candidate = Join-Path $BackupPath 'license-backup.json'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $jsonFile = $candidate
            }
        }

        if (-not $jsonFile -or -not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) {
            [pscustomobject]@{
                Success    = $false
                Restored   = @()
                Skipped    = @()
                Diffs      = @()
                BackupInfo = $null
                Message    = "Arquivo de backup nao encontrado: $BackupPath"
            }
            return
        }
    }
    else {
        [pscustomobject]@{
            Success    = $false
            Restored   = @()
            Skipped    = @()
            Diffs      = @()
            BackupInfo = $null
            Message    = 'Use -BackupPath <caminho> ou -AutoDiscover para localizar o backup.'
        }
        return
    }

    try {
        $backup = Get-Content -LiteralPath $jsonFile -Raw | ConvertFrom-Json
    }
    catch {
        [pscustomobject]@{
            Success    = $false
            Restored   = @()
            Skipped    = @()
            Diffs      = @()
            BackupInfo = $null
            Message    = "Falha ao ler backup: $($_.Exception.Message)"
        }
        return
    }

    if (-not $backup.BackupTimestamp -or -not $backup.ComputerName) {
        [pscustomobject]@{
            Success    = $false
            Restored   = @()
            Skipped    = @()
            Diffs      = @()
            BackupInfo = $backup
            Message    = 'Backup invalido: campos obrigatorios ausentes (BackupTimestamp, ComputerName).'
        }
        return
    }

    Write-Host ""
    Write-Host "  Backup encontrado:" -ForegroundColor Cyan
    Write-Host "    Arquivo:      $jsonFile"
    Write-Host "    Computador:   $($backup.ComputerName)"
    Write-Host "    Gerado em:    $($backup.BackupTimestamp)"
    if ($backup.LicenseInfo) {
        Write-Host "    Canal:        $($backup.LicenseInfo.Licenca.Canal)"
        Write-Host "    Status:       $($backup.LicenseInfo.Licenca.Status)"
        Write-Host "    Partial Key:  $($backup.LicenseInfo.Licenca.PartialProductKey)"
    }

    $currentProduct = Get-SoftwareLicensingProduct | Where-Object {
        $_.LicenseStatus -ne $null -and $_.LicenseStatus -gt 0
    } | Select-Object -First 1

    $currentService = Get-SoftwareLicensingService | Select-Object -First 1

    $diffs = [System.Collections.Generic.List[pscustomobject]]::new()

    $backupPartialKey = if ($backup.Product) { [string]$backup.Product.PartialProductKey } else { '' }
    $currentPartialKey = if ($currentProduct) { [string]$currentProduct.PartialProductKey } else { '' }

    if ($backupPartialKey -ne $currentPartialKey) {
        $diffs.Add([pscustomobject]@{
            Field    = 'PartialProductKey'
            Backup   = $backupPartialKey
            Current  = $currentPartialKey
            Restorable = $false
        })
    }

    $backupKms = if ($backup.Service) { [string]$backup.Service.KeyManagementServiceMachine } else { '' }
    $currentKms = if ($currentService) { [string]$currentService.KeyManagementServiceMachine } else { '' }

    if ($backupKms -ne $currentKms) {
        $diffs.Add([pscustomobject]@{
            Field    = 'KmsServer'
            Backup   = $(if ($backupKms) { $backupKms } else { '(nenhum)' })
            Current  = $(if ($currentKms) { $currentKms } else { '(nenhum)' })
            Restorable = $true
        })
    }

    $backupKmsPort = if ($backup.Service) { [string]$backup.Service.KeyManagementServicePort } else { '' }
    $currentKmsPort = if ($currentService) { [string]$currentService.KeyManagementServicePort } else { '' }

    if ($backupKmsPort -ne $currentKmsPort) {
        $diffs.Add([pscustomobject]@{
            Field    = 'KmsPort'
            Backup   = $(if ($backupKmsPort) { $backupKmsPort } else { '(padrao)' })
            Current  = $(if ($currentKmsPort) { $currentKmsPort } else { '(padrao)' })
            Restorable = $true
        })
    }

    $backupChannel = if ($backup.LicenseInfo) { [string]$backup.LicenseInfo.Licenca.Canal } else { '' }
    $currentCycle = Get-LicenseCycleStatus
    $currentChannel = if ($currentCycle) { [string]$currentCycle.Channel } else { '' }

    if ($backupChannel -ne $currentChannel) {
        $diffs.Add([pscustomobject]@{
            Field    = 'Channel'
            Backup   = $backupChannel
            Current  = $currentChannel
            Restorable = $false
        })
    }

    $backupHwid = if ($backup.Hardware) { [string]$backup.Hardware.HwidAtual } else { '' }
    $currentHwid = if (Get-Command -Name Get-LicenseHardwareContext -ErrorAction SilentlyContinue) {
        $hw = Get-LicenseHardwareContext
        if ($hw) { [string]$hw.HwidAtual } else { '' }
    } else { '' }

    if ($backupHwid -ne $currentHwid -and $backupHwid -and $currentHwid) {
        $diffs.Add([pscustomobject]@{
            Field    = 'HWID'
            Backup   = $backupHwid
            Current  = $currentHwid
            Restorable = $false
        })
    }

    if ($diffs.Count -eq 0) {
        Write-Host ""
        Write-Ok "Estado atual identico ao backup. Nenhuma diferenca detectada."
        [pscustomobject]@{
            Success    = $true
            Restored   = @()
            Skipped    = @()
            Diffs      = @()
            BackupInfo = $backup
            Message    = 'Estado identico ao backup.'
        }
        return
    }

    Write-Host ""
    Write-Host "  Diferencas encontradas:" -ForegroundColor Yellow
    foreach ($d in $diffs) {
        $color = if ($d.Restorable) { 'Green' } else { 'DarkGray' }
        $tag = if ($d.Restorable) { '[RESTORAVEL]' } else { '[AUDIT]' }
        Write-Host "    $($d.Field):" -ForegroundColor White
        Write-Host "      Backup:  $($d.Backup)" -ForegroundColor $color
        Write-Host "      Atual:   $($d.Current)" -ForegroundColor $color
        Write-Host "      $tag" -ForegroundColor $color
    }

    $restorable = @($diffs | Where-Object Restorable)
    $readOnly   = @($diffs | Where-Object { -not $_.Restorable })

    if ($restorable.Count -eq 0) {
        Write-Host ""
        Write-Info "Nenhuma diferenca restauravel. Diferencas de auditoria apenas."
        [pscustomobject]@{
            Success    = $true
            Restored   = @()
            Skipped    = $diffs
            Diffs      = $diffs
            BackupInfo = $backup
            Message    = 'Nenhuma diferenca restauravel.'
        }
        return
    }

    Write-Host ""
    Write-Host "  Restauravel: $($restorable.Count) | Somente leitura: $($readOnly.Count)" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host ""
        Write-Host "  DRY-RUN: operacoes que seriam executadas:" -ForegroundColor Yellow
        foreach ($r in $restorable) {
            switch ($r.Field) {
                'KmsServer' {
                    Write-Host "    slmgr.vbs /skms $($r.Backup)" -ForegroundColor Yellow
                }
                'KmsPort' {
                    Write-Host "    slmgr.vbs /skms :$($r.Backup)" -ForegroundColor Yellow
                }
            }
        }
        Write-Host "  Nenhuma alteracao aplicada." -ForegroundColor Yellow
        [pscustomobject]@{
            Success    = $true
            Restored   = @()
            Skipped    = @()
            Diffs      = $diffs
            BackupInfo = $backup
            Message    = 'DryRun concluido.'
        }
        return
    }

    if (-not $Force) {
        Write-Host ""
        $confirm = Read-Host "  Confirmar restauracao das configuracoes? (s/N)"
        if ($confirm -notmatch '^[SsYy]$') {
            Write-Host "  Restauracao cancelada pelo operador." -ForegroundColor Yellow
            [pscustomobject]@{
                Success    = $false
                Restored   = @()
                Skipped    = @()
                Diffs      = $diffs
                BackupInfo = $backup
                Message    = 'Cancelado pelo operador.'
            }
            return
        }
    }

    $restored = [System.Collections.Generic.List[string]]::new()
    $skipped  = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($r in $restorable) {
        switch ($r.Field) {
            'KmsServer' {
                $port = if ($backupKmsPort) { $backupKmsPort } else { '1688' }
                $kmsTarget = if ($r.Backup) { "$($r.Backup):$port" } else { ':' }
                Write-Host "  Restaurando KMS: $kmsTarget" -ForegroundColor Cyan
                $result = Invoke-Slmgr -ArgumentList '/skms', $kmsTarget -TimeoutSeconds 30
                if ($result.ExitCode -eq 0 -and -not $result.TimedOut) {
                    Write-Ok "    KMS restaurado."
                    $restored.Add('KmsServer')
                }
                else {
                    Write-Host "    [FALHA] slmgr retornou codigo $($result.ExitCode)" -ForegroundColor Red
                    $skipped.Add($r)
                }
            }
            'KmsPort' {
                Write-Host "  Restaurando porta KMS: $($r.Backup)" -ForegroundColor Cyan
                $server = if ($backupKms) { $backupKms } else { $currentKms }
                if ($server) {
                    $target = "$server`:$($r.Backup)"
                    $result = Invoke-Slmgr -ArgumentList '/skms', $target -TimeoutSeconds 30
                    if ($result.ExitCode -eq 0 -and -not $result.TimedOut) {
                        Write-Ok "    Porta KMS restaurada."
                        $restored.Add('KmsPort')
                    }
                    else {
                        Write-Host "    [FALHA] slmgr retornou codigo $($result.ExitCode)" -ForegroundColor Red
                        $skipped.Add($r)
                    }
                }
                else {
                    Write-Host "    [SKIP] Sem servidor KMS no backup para combinar com a porta." -ForegroundColor Yellow
                    $skipped.Add($r)
                }
            }
        }
    }

    foreach ($ro in $readOnly) {
        Write-Host "  [AUDIT] $($ro.Field): $($ro.Backup) vs $($ro.Current)" -ForegroundColor DarkGray
    }

    [pscustomobject]@{
        Success    = $restored.Count -gt 0
        Restored   = $restored.ToArray()
        Skipped    = $skipped.ToArray()
        Diffs      = $diffs.ToArray()
        BackupInfo = $backup
        Message    = "Restauradas: $($restored.Count) | Ignoradas: $($skipped.Count) | Auditoria: $($readOnly.Count)"
    }
}
