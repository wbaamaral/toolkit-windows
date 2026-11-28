function Test-SshConnectivity {
    <#
    .SYNOPSIS
        Testa conectividade SSH local (servico respondendo na porta).

    .DESCRIPTION
        Verifica se o servico sshd esta respondendo na porta configurada.
        Testa TCP connection e opcionalmente uma autenticacao basica.

    .PARAMETER Port
        Porta TCP para testar. Padrao: 22.

    .PARAMETER Host
        Host para conectar. Padrao: localhost.

    .PARAMETER TimeoutMs
        Timeout de conexao em milissegundos. Padrao: 3000.

    .OUTPUTS
        PSCustomObject com: ServiceResponding, PortOpen, Banner.

    .EXAMPLE
        Test-SshConnectivity

    .EXAMPLE
        Test-SshConnectivity -Host 192.168.4.249 -Port 2222
    #>
    [CmdletBinding()]
    param(
        [string]$Host = 'localhost',
        [ValidateRange(1, 65535)]
        [int]$Port = 22,
        [int]$TimeoutMs = 3000
    )

    $portOpen = $false
    $banner = $null
    $connectionMs = $null
    $tcpClient = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $connectTask = $tcpClient.ConnectAsync($Host, $Port)
        $portOpen = $connectTask.Wait($TimeoutMs)
        $stopwatch.Stop()
        if ($portOpen) { $connectionMs = [int]$stopwatch.ElapsedMilliseconds }

        if ($portOpen -and $tcpClient.Connected) {
            $stream = $tcpClient.GetStream()
            $stream.ReadTimeout = $TimeoutMs

            try {
                $buffer = New-Object byte[] 256
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -gt 0) {
                    $banner = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead).Trim()
                }
            }
            catch { Write-Verbose "Nao foi possivel ler banner: $($_.Exception.Message)" }

            $stream.Close()
        }
    }
    catch {
        Write-Verbose "Falha na conexao: $($_.Exception.Message)"
    }
    finally {
        if ($tcpClient) { $tcpClient.Dispose() }
    }

    # ConnectionMs e o tempo medido ate conectar (nulo quando a porta nao abriu); antes repetia o TimeoutMs.
    # ServiceResponding exige o banner do protocolo SSH, nao qualquer servico que responda na porta.
    [pscustomobject]@{
        Host             = $Host
        Port             = $Port
        PortOpen         = $portOpen
        ServiceResponding = [bool]($portOpen -and $banner -and $banner.StartsWith('SSH-'))
        Banner           = $banner
        ConnectionMs     = $connectionMs
    }
}
