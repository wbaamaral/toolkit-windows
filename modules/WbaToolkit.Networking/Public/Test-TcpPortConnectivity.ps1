function Test-TcpPortConnectivity {
    <#
    .SYNOPSIS
        Executa teste de conectividade TCP em porta informada.

    .DESCRIPTION
        Tenta estabelecer conexão TCP assíncrona no destino e porta especificados, respeitando o timeout.
        Retorna resultado padronizado com status Aberta, Timeout ou Falha.

    .PARAMETER TargetAddress
        Endereço IP ou nome DNS do destino.

    .PARAMETER Port
        Porta TCP a testar. Valores permitidos: 1–65535.

    .PARAMETER TimeoutSeconds
        Tempo limite de conexão em segundos. Valores permitidos: 1–60. Padrão: 5.

    .PARAMETER Direction
        Direção do teste: Inbound ou Outbound. Padrão: Outbound.

    .PARAMETER Scope
        Escopo da conectividade: LAN ou WAN. Padrão: WAN.

    .EXAMPLE
        Test-TcpPortConnectivity -TargetAddress '8.8.8.8' -Port 443

    .EXAMPLE
        Test-TcpPortConnectivity -TargetAddress '10.0.0.1' -Port 3389 -Scope LAN -TimeoutSeconds 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetAddress,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 5,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Inbound', 'Outbound')]
        [string]$Direction = 'Outbound',

        [Parameter(Mandatory = $false)]
        [ValidateSet('LAN', 'WAN')]
        [string]$Scope = 'WAN'
    )

    $startedAt = Get-Date
    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $async = $client.BeginConnect($TargetAddress, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)) {
            # Timeout: nao chamamos EndConnect (bloquearia ate o connect completar/falhar).
            # Dispose aborta o connect assincrono pendente e libera o socket.
            $client.Dispose()
            return New-ConnectivityResult -TestName 'Teste TCP' -Category 'Porta' -Protocol 'TCP' -Direction $Direction -Scope $Scope `
                -Target $TargetAddress -Port $Port -Success $false -Status 'Timeout' -Classification 'Failed' `
                -Recommendation 'Timeout: verifique firewall, rota, NAT ou serviço indisponível.' -StartedAt $startedAt -FinishedAt (Get-Date)
        }

        $client.EndConnect($async)
        $latency = [math]::Round((Get-Date).Subtract($startedAt).TotalMilliseconds, 1)
        New-ConnectivityResult -TestName 'Teste TCP' -Category 'Porta' -Protocol 'TCP' -Direction $Direction -Scope $Scope `
            -Target $TargetAddress -Port $Port -Success $true -Status 'Aberta' -Classification 'Success' -LatencyMs $latency `
            -Recommendation 'Conectividade TCP validada com sucesso.' -StartedAt $startedAt -FinishedAt (Get-Date)
    }
    catch {
        New-ConnectivityResult -TestName 'Teste TCP' -Category 'Porta' -Protocol 'TCP' -Direction $Direction -Scope $Scope `
            -Target $TargetAddress -Port $Port -Success $false -Status 'Falha' -Classification 'Failed' -ErrorMessage $_.Exception.Message `
            -Recommendation 'Verifique firewall, serviço de destino e rota.' -StartedAt $startedAt -FinishedAt (Get-Date)
    }
    finally {
        if ($client) { $client.Dispose() }
    }
}
