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

    $vssService = $null
    try { $vssService = Get-Service -Name 'VSS' -ErrorAction Stop }
    catch { Write-Verbose "Servico VSS indisponivel: $($_.Exception.Message)" }
    $checks.Add([pscustomobject]@{
        Name    = 'Servico VSS'
        Status  = if ($vssService -and $vssService.Status -eq 'Running') { 'OK' } else { 'FALHA' }
        Detail  = if ($vssService) { $vssService.Status.ToString() } else { 'Nao encontrado' }
    })

    $sysRestore = $null
    try { $sysRestore = Get-Service -Name 'swprv' -ErrorAction Stop }
    catch { Write-Verbose "Servico swprv indisponivel: $($_.Exception.Message)" }
    $checks.Add([pscustomobject]@{
        Name    = 'Servico System Restore'
        Status  = if ($sysRestore -and $sysRestore.Status -eq 'Running') { 'OK' } else { 'AVISO' }
        Detail  = if ($sysRestore) { $sysRestore.Status.ToString() } else { 'Nao encontrado' }
    })

    $fixedVolumes = @()
    try { $fixedVolumes = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }) }
    catch { Write-Verbose "Nao foi possivel consultar volumes fixos: $($_.Exception.Message)" }

    foreach ($vol in $fixedVolumes) {
        $freePercent = if ($vol.Size -gt 0) { [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }
        $status = if ($freePercent -ge 15) { 'OK' } elseif ($freePercent -ge 5) { 'AVISO' } else { 'FALHA' }

        $checks.Add([pscustomobject]@{
            Name    = "Espaco disco $($vol.DriveLetter):"
            Status  = $status
            Detail  = "Livre: $($vol.SizeRemaining / 1GB) GB ($freePercent%) de $($vol.Size / 1GB) GB"
        })
    }

    $shadowCount = 0
    try { $shadowCount = (Get-CimInstance Win32_ShadowCopy -ErrorAction Stop | Measure-Object).Count }
    catch { Write-Verbose "Nao foi possivel consultar copias de sombra: $($_.Exception.Message)" }
    $checks.Add([pscustomobject]@{
        Name    = 'Shadow Copies existentes'
        Status  = 'INFO'
        Detail  = "$shadowCount shadow copy(s)"
    })

    $restorePoints = @()
    try { $restorePoints = @(Get-ComputerRestorePoint -ErrorAction Stop) }
    catch { Write-Verbose "Nao foi possivel consultar pontos de restauracao: $($_.Exception.Message)" }
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
