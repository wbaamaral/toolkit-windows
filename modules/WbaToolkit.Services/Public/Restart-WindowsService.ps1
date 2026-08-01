function Restart-WindowsService {
    <#
    .SYNOPSIS
        Reinicia um ou mais servicos Windows.

    .DESCRIPTION
        Para e inicia servico(s). Se o servico estiver parado, apenas inicia.
        Suporta skip se o servico ja estiver parado.

    .PARAMETER Name
        Nome(s) do(s) servico(s) a reiniciar.

    .PARAMETER SkipIfStopped
        Nao inicia servicos que estavam parados.

    .PARAMETER TimeoutSeconds
        Tempo maximo de espera para parar antes de iniciar. Padrao: 30.

    .OUTPUTS
        PSCustomObject com: Success, Message, ServiceName, Changes.

    .EXAMPLE
        Restart-WindowsService -Name 'W32Time'

    .EXAMPLE
        Restart-WindowsService -Name 'Spooler', 'WSearch' -SkipIfStopped
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [switch]$SkipIfStopped,

        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    if (-not (Test-IsAdministrator)) {
        return Format-ServiceResult -Success $false -Message 'A operacao exige privilegios administrativos.'
    }

    $allResults = [System.Collections.Generic.List[object]]::new()

    foreach ($svcName in $Name) {
        $resolved = Resolve-WindowsService -Name $svcName
        if (-not $resolved.Exists) {
            $allResults.Add((Format-ServiceResult -Success $false -Message $resolved.Message -ServiceName $svcName))
            continue
        }

        $svc = $resolved.Service
        $wasRunning = $svc.Status -eq 'Running'

        if ($svc.Status -eq 'Stopped' -and $SkipIfStopped) {
            $allResults.Add((Format-ServiceResult -Success $true -Message "Servico '$svcName' estava parado, ignorado (-SkipIfStopped)." -ServiceName $svcName))
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($svcName, 'Reiniciar servico')) {
            $allResults.Add((Format-ServiceResult -Success $true -Message "Reinicio de '$svcName' ignorado por WhatIf." -ServiceName $svcName))
            continue
        }

        $stopResult = Stop-WindowsService -Name $svcName -TimeoutSeconds $TimeoutSeconds -Confirm:$false
        if (-not $stopResult.Success -and $svc.Status -ne 'Stopped') {
            $allResults.Add((Format-ServiceResult -Success $false -Message "Falha ao parar '$svcName' para reinicio: $($stopResult.Message)" -ServiceName $svcName))
            continue
        }

        $startResult = Start-WindowsService -Name $svcName
        if ($startResult.Success) {
            $changes = @()
            if (-not $wasRunning) { $changes += 'WasStopped' }
            $changes += 'Restarted'
            $allResults.Add((Format-ServiceResult -Success $true -Message "Servico '$svcName' reiniciado com sucesso." -ServiceName $svcName -Changes $changes))
        }
        else {
            $allResults.Add((Format-ServiceResult -Success $false -Message "Servico '$svcName' parado mas falhou ao iniciar: $($startResult.Message)" -ServiceName $svcName))
        }
    }

    if ($allResults.Count -eq 1) { return $allResults[0] }
    @($allResults)
}
