function Test-VssHealth {
    <#
    .SYNOPSIS
        Verifica a saude do servico VSS e espaco em disco.
    .DESCRIPTION
        Checa status do servico VSS, espaco livre em discos e protecao do sistema.
    .OUTPUTS
        PSCustomObject com checks de saude.
    #>
    [CmdletBinding()]
    param()

    $checks = [System.Collections.Generic.List[pscustomobject]]::new()

    $vssService = Get-Service -Name 'VSS' -ErrorAction SilentlyContinue
    $checks.Add([pscustomobject]@{
        Name    = 'Servico VSS'
        Status  = if ($vssService -and $vssService.Status -eq 'Running') { 'OK' } else { 'FALHA' }
        Detail  = if ($vssService) { $vssService.Status.ToString() } else { 'Nao encontrado' }
    })

    $sysRestore = Get-Service -Name 'swprv' -ErrorAction SilentlyContinue
    $checks.Add([pscustomobject]@{
        Name    = 'Servico System Restore'
        Status  = if ($sysRestore -and $sysRestore.Status -eq 'Running') { 'OK' } else { 'AVISO' }
        Detail  = if ($sysRestore) { $sysRestore.Status.ToString() } else { 'Nao encontrado' }
    })

    $fixedVolumes = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }

    foreach ($vol in $fixedVolumes) {
        $freePercent = if ($vol.Size -gt 0) { [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }
        $status = if ($freePercent -ge 15) { 'OK' } elseif ($freePercent -ge 5) { 'AVISO' } else { 'FALHA' }

        $checks.Add([pscustomobject]@{
            Name    = "Espaco disco $($vol.DriveLetter):"
            Status  = $status
            Detail  = "Livre: $($vol.SizeRemaining / 1GB) GB ($freePercent%) de $($vol.Size / 1GB) GB"
        })
    }

    $shadowCount = (Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue | Measure-Object).Count
    $checks.Add([pscustomobject]@{
        Name    = 'Shadow Copies existentes'
        Status  = 'INFO'
        Detail  = "$shadowCount shadow copy(s)"
    })

    $restorePoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    $rpCount = ($restorePoints | Measure-Object).Count
    $checks.Add([pscustomobject]@{
        Name    = 'Restore Points existentes'
        Status  = 'INFO'
        Detail  = "$rpCount restore point(s)"
    })

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        CheckedAt    = Get-Date
        Checks       = $checks
        Healthy      = ($checks | Where-Object { $_.Status -eq 'FALHA' }).Count -eq 0
    }
}
