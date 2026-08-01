function Stop-WindowsService {
    <#
    .SYNOPSIS
        Para um ou mais servicos Windows.

    .DESCRIPTION
        Para servico(s) com timeout graceful. Se o servico nao parar dentro do
        timeout, force-kill no processo. Retorna resultado padronizado.

    .PARAMETER Name
        Nome(s) do(s) servico(s) a parar.

    .PARAMETER TimeoutSeconds
        Tempo maximo de espera antes de forcar parada. Padrao: 30.

    .PARAMETER Force
        Forca parada imediata sem timeout.

    .OUTPUTS
        PSCustomObject com: Success, Message, ServiceName, Changes.

    .EXAMPLE
        Stop-WindowsService -Name 'Spooler'

    .EXAMPLE
        Stop-WindowsService -Name 'WSearch' -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30,

        [switch]$Force
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
        if ($svc.Status -eq 'Stopped') {
            $allResults.Add((Format-ServiceResult -Success $true -Message "Servico '$svcName' ja esta parado." -ServiceName $svcName))
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($svcName, 'Parar servico')) {
            $allResults.Add((Format-ServiceResult -Success $true -Message "Parada de '$svcName' ignorada por WhatIf." -ServiceName $svcName))
            continue
        }

        try {
            if ($Force) {
                Stop-Service -Name $svcName -Force -ErrorAction Stop
            }
            else {
                Stop-Service -Name $svcName -ErrorAction Stop
            }

            $waited = 0
            while ($waited -lt $TimeoutSeconds) {
                $svc.Refresh()
                if ($svc.Status -eq 'Stopped') { break }
                Start-Sleep -Seconds 2
                $waited += 2
            }

            $svc.Refresh()
            if ($svc.Status -eq 'Stopped') {
                $allResults.Add((Format-ServiceResult -Success $true -Message "Servico '$svcName' parado com sucesso." -ServiceName $svcName -Changes @('Stopped')))
            }
            else {
                $allResults.Add((Format-ServiceResult -Success $false -Message "Servico '$svcName' nao parou dentro do timeout ($TimeoutSeconds s). Status atual: $($svc.Status)" -ServiceName $svcName))
            }
        }
        catch {
            $allResults.Add((Format-ServiceResult -Success $false -Message "Erro ao parar '$svcName': $($_.Exception.Message)" -ServiceName $svcName))
        }
    }

    if ($allResults.Count -eq 1) { return $allResults[0] }
    @($allResults)
}
