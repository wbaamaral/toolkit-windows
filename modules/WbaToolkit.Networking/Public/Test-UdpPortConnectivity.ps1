function Test-UdpPortConnectivity {
    <#
    .SYNOPSIS
        Executa teste UDP com deteccao de porta fechada via ICMP e classifica o resultado.

    .DESCRIPTION
        Envia um datagrama UDP ao destino usando um socket "conectado" (que fixa o peer e habilita
        a entrega de erros ICMP referentes a ele) e aguarda resposta ate TimeoutSeconds:

          - Resposta recebida           -> Aberta      (Classification Success)
          - ICMP porta inalcancavel     -> Fechada     (Classification Failed; SocketError ConnectionReset)
          - Sem resposta dentro do timeout -> Sem resposta (Classification Inconclusive: aberta sem eco ou filtrada)

        UDP e sem conexao: a ausencia de resposta nao distingue "aberta sem eco" de "filtrada", por isso
        esse caso permanece inconclusivo.

    .PARAMETER TargetAddress
        Endereço IP ou nome DNS do destino.

    .PARAMETER Port
        Porta UDP a testar. Valores permitidos: 1–65535.

    .PARAMETER TimeoutSeconds
        Tempo limite, em segundos, para aguardar resposta/ICMP do destino. Valores permitidos: 1–60. Padrão: 5.

    .PARAMETER Direction
        Direção do teste: Inbound ou Outbound. Padrão: Outbound.

    .PARAMETER Scope
        Escopo da conectividade: LAN ou WAN. Padrão: WAN.

    .EXAMPLE
        Test-UdpPortConnectivity -TargetAddress '10.0.0.1' -Port 53

    .EXAMPLE
        Test-UdpPortConnectivity -TargetAddress '192.168.1.1' -Port 161 -Scope LAN
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
    $socket = $null
    try {
        $socket = New-Object System.Net.Sockets.Socket(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp)
        $socket.ReceiveTimeout = $TimeoutSeconds * 1000

        # Connect num socket UDP nao abre conexao, mas fixa o peer e habilita o recebimento
        # de erros ICMP (porta inalcancavel) referentes a esse destino.
        $socket.Connect($TargetAddress, $Port)
        [void]$socket.Send([byte[]](1, 2, 3, 4))

        $buffer = New-Object byte[] 512
        try {
            [void]$socket.Receive($buffer)
            New-ConnectivityResult -TestName 'Teste UDP' -Category 'Porta' -Protocol 'UDP' -Direction $Direction -Scope $Scope `
                -Target $TargetAddress -Port $Port -Success $true -Status 'Aberta' -Classification 'Success' `
                -Recommendation 'Destino UDP respondeu ao datagrama de teste.' -StartedAt $startedAt -FinishedAt (Get-Date)
        }
        catch [System.Net.Sockets.SocketException] {
            switch ($_.Exception.SocketErrorCode) {
                'ConnectionReset' {
                    # ICMP Port Unreachable -> porta fechada no destino.
                    New-ConnectivityResult -TestName 'Teste UDP' -Category 'Porta' -Protocol 'UDP' -Direction $Direction -Scope $Scope `
                        -Target $TargetAddress -Port $Port -Success $false -Status 'Fechada' -Classification 'Failed' `
                        -ErrorMessage 'ICMP porta inalcancavel (Connection reset).' `
                        -Recommendation 'Porta UDP fechada no destino (ICMP port-unreachable).' -StartedAt $startedAt -FinishedAt (Get-Date)
                }
                'TimedOut' {
                    # Sem resposta dentro do timeout -> aberta sem eco ou filtrada (inconclusivo).
                    New-ConnectivityResult -TestName 'Teste UDP' -Category 'Porta' -Protocol 'UDP' -Direction $Direction -Scope $Scope `
                        -Target $TargetAddress -Port $Port -Success $true -Status 'Sem resposta' -Classification 'Inconclusive' `
                        -Recommendation 'Sem resposta UDP dentro do timeout: porta aberta sem eco ou filtrada (inconclusivo).' `
                        -StartedAt $startedAt -FinishedAt (Get-Date)
                }
                default { throw }
            }
        }
    }
    catch {
        New-ConnectivityResult -TestName 'Teste UDP' -Category 'Porta' -Protocol 'UDP' -Direction $Direction -Scope $Scope `
            -Target $TargetAddress -Port $Port -Success $false -Status 'Falha' -Classification 'Failed' -ErrorMessage $_.Exception.Message `
            -Recommendation 'Verifique conectividade de rede e filtragem UDP.' -StartedAt $startedAt -FinishedAt (Get-Date)
    }
    finally {
        if ($socket) { $socket.Dispose() }
    }
}
