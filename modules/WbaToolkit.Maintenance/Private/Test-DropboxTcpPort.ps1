# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxTcpPort {
    <#
    .SYNOPSIS
        Testa conectividade TCP com um destino e porta, com timeout.

    .DESCRIPTION
        Fronteira isolada e mockavel sobre System.Net.Sockets.TcpClient, no mesmo
        padrao de Test-TcpPortConnectivity do WbaToolkit.Networking (BeginConnect
        assincrono + WaitOne, sem chamar EndConnect apos timeout).

    .PARAMETER HostName
        Endereco IP ou nome DNS do destino.

    .PARAMETER Port
        Porta TCP a testar.

    .PARAMETER TimeoutMs
        Tempo limite em milissegundos. Padrao 3000.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMs = 3000
    )

    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $client.Dispose()
            return $false
        }
        $client.EndConnect($async)
        return $true
    }
    catch {
        Write-Verbose "Falha ao testar conectividade TCP com ${HostName}:${Port}: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($client) { $client.Dispose() }
    }
}
