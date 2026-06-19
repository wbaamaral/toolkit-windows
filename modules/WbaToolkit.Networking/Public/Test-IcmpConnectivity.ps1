function Test-IcmpConnectivity {
    <#
    .SYNOPSIS
        Executa teste ICMP contra um destino informado.

    .DESCRIPTION
        Usa Test-Connection para enviar pacotes ICMP ao endereço informado e calcula a latência média.
        Retorna um objeto de resultado padronizado com classificação Success ou Failed.

    .PARAMETER TargetAddress
        Endereço IP ou nome DNS do destino a ser testado.

    .PARAMETER Count
        Número de pacotes ICMP a enviar. Valores permitidos: 1–10. Padrão: 3.

    .PARAMETER TimeoutSeconds
        Tempo limite de espera por resposta em segundos. Valores permitidos: 1–60. Padrão: 5.

    .EXAMPLE
        Test-IcmpConnectivity -TargetAddress '8.8.8.8'

    .EXAMPLE
        Test-IcmpConnectivity -TargetAddress '192.168.1.1' -Count 2 -TimeoutSeconds 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetAddress,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$Count = 3,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 5
    )

    $startedAt = Get-Date
    try {
        $reply = Test-Connection -ComputerName $TargetAddress -Count $Count -ErrorAction Stop
        $latency = $null
        if ($reply) {
            # Windows PowerShell 5.1 expoe 'ResponseTime'; PowerShell 7+ expoe 'Latency'.
            $latencyProperty = if ((@($reply)[0].PSObject.Properties.Name) -contains 'Latency') { 'Latency' } else { 'ResponseTime' }
            $avgLatency = ($reply | Measure-Object -Property $latencyProperty -Average).Average
            if ($null -ne $avgLatency) { $latency = [math]::Round($avgLatency, 1) }
        }

        New-ConnectivityResult -TestName 'Teste ICMP' -Category 'ICMP' -Protocol 'ICMP' -Direction 'Outbound' -Scope 'WAN' `
            -Target $TargetAddress -Success $true -Status 'Respondendo' -Classification 'Success' -LatencyMs $latency `
            -Recommendation 'Conectividade ICMP validada com sucesso.' -StartedAt $startedAt -FinishedAt (Get-Date)
    }
    catch {
        New-ConnectivityResult -TestName 'Teste ICMP' -Category 'ICMP' -Protocol 'ICMP' -Direction 'Outbound' -Scope 'WAN' `
            -Target $TargetAddress -Success $false -Status 'Sem resposta' -Classification 'Failed' -ErrorMessage $_.Exception.Message `
            -Recommendation 'Verifique firewall, rota ou indisponibilidade do destino.' -StartedAt $startedAt -FinishedAt (Get-Date)
    }
}
