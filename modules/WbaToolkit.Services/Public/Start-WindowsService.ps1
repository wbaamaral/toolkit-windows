function Start-WindowsService {
    <#
    .SYNOPSIS
        Inicia um ou mais servicos Windows.

    .DESCRIPTION
        Inicia servico(s) com retry configuravel. Retorna resultado padronizado
        para cada servico processado.

    .PARAMETER Name
        Nome(s) do(s) servico(s) a iniciar.

    .PARAMETER RetryCount
        Numero de tentativas apos falha. Padrao: 2.

    .PARAMETER RetryDelaySeconds
        Intervalo entre tentativas em segundos. Padrao: 3.

    .OUTPUTS
        PSCustomObject com: Success, Message, ServiceName, Changes.

    .EXAMPLE
        Start-WindowsService -Name 'W32Time'

    .EXAMPLE
        Start-WindowsService -Name 'W32Time', 'Spooler' -RetryCount 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [ValidateRange(0, 10)]
        [int]$RetryCount = 2,

        [ValidateRange(1, 60)]
        [int]$RetryDelaySeconds = 3
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
        if ($svc.Status -eq 'Running') {
            $allResults.Add((Format-ServiceResult -Success $true -Message "Servico '$svcName' ja esta em execucao." -ServiceName $svcName))
            continue
        }

        $attempts = 0
        $started = $false
        while ($attempts -le $RetryCount) {
            try {
                Start-Service -Name $svcName -ErrorAction Stop
                $started = $true
                break
            }
            catch {
                $attempts++
                if ($attempts -le $RetryCount) {
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }
        }

        if ($started) {
            $allResults.Add((Format-ServiceResult -Success $true -Message "Servico '$svcName' iniciado com sucesso." -ServiceName $svcName -Changes @('Started')))
        }
        else {
            $allResults.Add((Format-ServiceResult -Success $false -Message "Falha ao iniciar '$svcName' apos $($RetryCount + 1) tentativa(s)." -ServiceName $svcName))
        }
    }

    if ($allResults.Count -eq 1) { return $allResults[0] }
    @($allResults)
}
