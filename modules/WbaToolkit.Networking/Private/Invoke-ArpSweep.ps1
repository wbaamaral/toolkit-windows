function Invoke-ArpSweep {
    <#
    .SYNOPSIS
        Varredura ARP de uma lista de IPs: faz ping assincrono e coleta a tabela ARP.

    .DESCRIPTION
        Envia pacotes ICMP em paralelo (chunks de tamanho Throttle) para popular
        o cache ARP local, depois coleta os pares IP x MAC usando Get-NetNeighbor
        quando disponivel (Windows 8+/Server 2012+), com fallback para arp -a.

        Nao e uma varredura 'scanner': apos a fase de ping, apenas os pares ja
        presentes no cache ARP sao lidos. Hosts que nao respondem ao ICMP nao
        terao entrada ARP.

    .PARAMETER IpList
        Lista de enderecos IPv4 a varrer. Use ConvertFrom-IpRange para expandir
        CIDR ou intervalos.

    .PARAMETER TimeoutMs
        Tempo de espera por host em milissegundos. Default 500ms e o equilibrio
        tipico entre rapidez e captura de hosts lentos em LAN.

    .PARAMETER Throttle
        Numero maximo de pings simultaneos. Default 50. Valores acima disso
        podem esgotar portas efemeras ou confundir IDS/IPS.

    .PARAMETER Interface
        Alias da interface de rede (ex.: 'Ethernet0') para filtrar a coleta
        ARP. Se omitido, coleta de todas as interfaces.

    .EXAMPLE
        Invoke-ArpSweep -IpList @('192.168.1.1','192.168.1.2') -TimeoutMs 400

    .NOTES
        Privada do modulo WbaToolkit.Networking. Nao executa footer do terminal.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[pscustomobject]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$IpList,

        [Parameter(Mandatory = $false)]
        [ValidateRange(50, 5000)]
        [int]$TimeoutMs = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 500)]
        [int]$Throttle = 50,

        [Parameter(Mandatory = $false)]
        [string]$Interface
    )

    # --- Fase 1: ping assincrono em chunks para popular ARP ----------------
    # SendPingAsync retorna System.Threading.Tasks.Task. Agrupamos em chunks de
    # $Throttle e chamamos [Task]::WaitAll bloqueando so na chunk atual; dentro
    # da chunk os pings rodam em paralelo. E o padrao compativel com PS 5.1.

    $total = $IpList.Count
    $processed = 0

    for ($chunkStart = 0; $chunkStart -lt $total; $chunkStart += $Throttle) {
        $chunkEnd = [math]::Min($chunkStart + $Throttle, $total) - 1
        $slice    = $IpList[$chunkStart..$chunkEnd]

        # Para cada IP: cria um Ping, dispara o ping async e guarda a task.
        # O objeto Ping implementa IDisposable, portanto criamos um paralelo
        # para garantir o Dispose apos [Task]::WaitAll.
        $pings = New-Object System.Collections.Generic.List[object]
        $tasks = New-Object System.Collections.Generic.List[object]

        foreach ($ip in $slice) {
            $ping = [System.Net.NetworkInformation.Ping]::new()
            $pings.Add(@{ Instance = $ping; Ip = $ip })
            try {
                $tasks.Add($ping.SendPingAsync($ip, $TimeoutMs))
            } catch {
                # PingException no envio (ex.: rota invalida local) ignora-se;
                # o host sera baixado da lista ARP ou ausente na coleta.
                Write-Verbose "Falha ao iniciar ping para ${ip}: $($_.Exception.Message)"
            }
        }

        # Aguarda todas as task da chunk atual em paralelo.
        if ($tasks.Count -gt 0) {
            try {
                [System.Threading.Tasks.Task]::WaitAll($tasks.ToArray())
            } catch [System.AggregateException] {
                # AggregateException封装 PingException de cada host; e esperado
                # para hosts inalcancaveis e nao deve abortar a varredura.
                Write-Verbose 'Alguns pings na chunk falharam (esperado para hosts offline).'
            }
        }

        # Libera os recursos de cada Ping (sockets ICMP).
        foreach ($p in $pings) {
            try { $p.Instance.Dispose() } catch { }
        }

        $processed = $chunkEnd + 1
        $pct = [int](($processed / $total) * 100)
        Write-Verbose ("[ARP] {0}% ({1}/{2})" -f $pct, $processed, $total)
    }

    # --- Fase 2: coleta da tabela ARP -------------------------------------
    # Prioriza Get-NetNeighbor (obj. estruturado, independente de idioma).
    # Se ausente (PowerShell <3 ou erro), cai em arp -a com regex robusto.

    $rawEntries = $null

    if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
        try {
            # State filter omite estados uninteresting (ex.: 'Incomplete').
            # Usa -ErrorAction SilentlyContinue porque cmdlet pode estar presente
            # mas restrito em alguns ambientes (limite por GPO).
            if ($Interface) {
                # Resolve o InterfaceIndex a partir do alias; fallback -InterfaceAlias
                $ifIndex = $null
                try {
                    $netAdapter = Get-NetAdapter -Name $Interface -ErrorAction Stop
                    $ifIndex = $netAdapter.ifIndex
                } catch {
                    Write-Warning "Interface nao encontrada: $Interface (continua sem filtro)."
                }
                if ($ifIndex) {
                    $rawEntries = Get-NetNeighbor -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                } else {
                    $rawEntries = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue
                }
            } else {
                $rawEntries = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Verbose "Get-NetNeighbor falhou: $($_.Exception.Message) — tentando arp -a."
            $rawEntries = $null
        }
    }

    # Fallback: parse textual de arp -a. Regex aceita separador '-' ou ':' no
    # MAC (sistemas pt-BR usam '-', en-US usam ':').
    if ($null -eq $rawEntries) {
        try {
            if ($Interface) {
                $rawText = arp -a -N $Interface 2>$null
            } else {
                $rawText = arp -a 2>$null
            }
        } catch {
            Write-Warning "arp -a falhou: $($_.Exception.Message)."
            return @()
        }

        # Captura "(IP separado por espacos) MAC separador '-' ou ':'"
        # Linhas de cabecalho/texto de interface nao casam e sao descartadas.
        $macRegex = '([0-9a-fA-F]{2}[-:]){5}[0-9a-fA-F]{2}'
        # Build the pattern separately for Windows PowerShell 5.1. Keeping
        # the regex in a single-quoted literal avoids parser ambiguity around
        # backslashes and the interpolated variable in a double-quoted string.
        $ipPattern = '\b(\d{1,3}\.){3}\d{1,3}\b\s+' + $macRegex
        $rawEntries = $rawText | Select-String -Pattern $ipPattern | ForEach-Object {
            $line = $_.ToString()
            $ipMatch  = [regex]::Match($line, '(\d{1,3}\.){3}\d{1,3}')
            $macMatch = [regex]::Match($line, $macRegex)
            [pscustomobject]@{
                IPAddress        = $ipMatch.Value
                LinkLayerAddress = $macMatch.Value
            }
        }
    }

    # --- Filtragem e normalizacao ------------------------------------------

    $ipSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$IpList, [System.StringComparer]::OrdinalIgnoreCase
    )
    $blankMac = '00-00-00-00-00-00', '00:00:00:00:00:00', 'ff-ff-ff-ff-ff-ff', 'ff:ff:ff:ff:ff:ff'
    $results  = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($entry in $rawEntries) {
        $ip  = [string]$entry.IPAddress
        $mac = [string]$entry.LinkLayerAddress

        if (-not $ipSet.Contains($ip)) { continue }
        # Ignora entradas incompletas/zero/broadcast (nao representam host real).
        if ([string]::IsNullOrWhiteSpace($mac)) { continue }
        $macNorm = $mac.ToLower().Replace(':', '-')
        if ($blankMac -contains $macNorm) { continue }

        $results.Add([pscustomobject]@{
            IP  = $ip
            MAC = $macNorm
        })
    }

    return $results
}
