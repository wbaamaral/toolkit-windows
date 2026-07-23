function Detect-DuplicateIp {
    <#
    .SYNOPSIS
        Detecta IPs associados a multiplos enderecos MAC em uma faixa de rede.

    .DESCRIPTION
        Orquestra o ciclo completo de deteccao:

          1. Expande a faixa informada (CIDR, intervalo, intervalo compacto ou IP unico).
          2. Varre a faixa com ping ICMP assincrono para popular o cache ARP local.
          3. Coleta os pares IP x MAC (Get-NetNeighbor ou arp -a).
          4. Agrupa por IP e marca como DUPLICADO os que possuem mais de um MAC.
          5. Gera tres relatorios (TXT, Markdown, HTML) na pasta de saida.

        Nao exige privilegios administrativos: ping e leitura do cache ARP sao
        operacoes de usuario comum no Windows.

    .PARAMETER Range
        Faixa no formato CIDR ("192.168.1.0/24"), intervalo completo
        ("192.168.1.1-192.168.1.254"), intervalo compacto ("192.168.1.10-50")
        ou IP unico ("192.168.1.5"). Nao e possivel misturar formatos.

    .PARAMETER Interface
        Alias da interface de rede para filtrar a coleta ARP (ex.: "Ethernet0").
        Se omitido, coleta de todas as interfaces. Ignorado se a coleta fallback
        para arp -a nao encontrar a interface informada.

    .PARAMETER OutputPath
        Diretorio onde os tres relatorios serao gravados. Se omitido, usa
        <ReportsRoot>/detectar-ip-duplicado/<ddMMyyyy_HHmmss>/, conforme
        padrao-saida-relatorios.md do toolkit.

    .PARAMETER TimeoutMs
        Tempo de espera por host em milissegundos. Default 500ms.

    .PARAMETER Throttle
        Numero maximo de pings simultaneos. Default 50.

    .EXAMPLE
        Detect-DuplicateIp -Range '192.168.1.0/24'

    .EXAMPLE
        Detect-DuplicateIp -Range '192.168.1.10-50' -Interface 'Ethernet0' -TimeoutMs 400

    .EXAMPLE
        Detect-DuplicateIp -Range '192.168.1.1-192.168.1.254' -OutputPath 'C:\Temp\arp-relatorios'

    .OUTPUTS
        [pscustomobject[]] Um objeto por IP encontrado com as propriedades IP,
        MACs (string separada por virgula) e Status (DUPLICADO ou OK).

    .NOTES
        Projeto: wba-toolkit
        Autor: wbaamaral
        Modulo: WbaToolkit.Networking
        Modulos requeridos: WbaToolkit.Core
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Range,

        [Parameter(Mandatory = $false)]
        [string]$Interface,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(50, 5000)]
        [int]$TimeoutMs = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 500)]
        [int]$Throttle = 50
    )

    # === ETAPA 1: validacao e expansao da faixa de IP =====================
    # Delegamos o parsing para ConvertFrom-IpRange, que aceita CIDR, intervalo
    # completo, intervalo compacto e IP unico. O throw em caso de formato
    # invalido sobe ate quem chamou (comportamento correto: param invalido).
    Write-Verbose "Expandindo faixa: $Range"
    $ipList = ConvertFrom-IpRange -Range $Range

    if ($ipList.Count -eq 0) {
        Write-Warning 'Faixa expandida sem enderecos validos; nada a fazer.'
        return @()
    }
    Write-Verbose ("Total de IPs a varrer: {0}" -f $ipList.Count)

    # === ETAPA 2: varredura ARP (ping async + coleta cache) ===============
    # Invoke-ArpSweep envia pings em paralelo (chunks de Throttle) e depois
    # le o cache ARP via Get-NetNeighbor (ou arp -a como fallback). Retorna
    # apenas os pares cujo IP esta dentro da faixa passada.
    Write-Verbose "Iniciando varredura ARP (timeout ${TimeoutMs}ms, throttle ${Throttle})..."
    $arpPairs = Invoke-ArpSweep `
        -IpList $ipList `
        -TimeoutMs $TimeoutMs `
        -Throttle $Throttle `
        -Interface $Interface

    Write-Verbose ("Pares IP x MAC coletados: {0}" -f $arpPairs.Count)

    # === ETAPA 3: agrupamento e deteccao de duplicados ====================
    # Para cada IP, junta os MACs associados em uma string separada por
    # virgula. Se um IP tem mais de uma entrada no cache ARP, e porque
    # respondesse a MACs diferentes — sinal classico de IP duplicado.
    $grouped = $arpPairs | Group-Object -Property IP
    $results = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($group in $grouped) {
        $macs = @($group.Group.MAC | Sort-Object -Unique)
        $status = if ($macs.Count -gt 1) { 'DUPLICADO' } else { 'OK' }
        $results.Add([pscustomobject]@{
            IP     = $group.Name
            MACs   = ($macs -join ', ')
            Status = $status
        })
    }

    # Garante ordem estavel para o relatorio: duplicados primeiro, depois IP.
    $results = @($results | Sort-Object @{Expression = 'Status'; Descending = $true}, 'IP')

    $totalDup = @($results | Where-Object Status -eq 'DUPLICADO').Count

    # Um IP ocupado e aquele que apareceu no cache ARP; o mesmo IP pode ter
    # mais de um MAC, mas continua contando uma vez como ocupado. Os demais
    # enderecos consultados sao exibidos como livres, com a ressalva de que
    # ausencia no ARP nao prova que o host esteja definitivamente livre.
    $occupiedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pair in $arpPairs) { [void]$occupiedSet.Add([string]$pair.IP) }
    $freeIps = @($ipList | Where-Object { -not $occupiedSet.Contains($_) })
    $totalOccupied = $occupiedSet.Count
    $totalFree = $freeIps.Count

    # === ETAPA 4: definicao do local de saida dos relatorios =============
    # OutputPath e a raiz opcional escolhida pelo operador. A sessao Core
    # sempre cria <ReportsRoot>/<modulo>/<timestamp>/, inclusive em chamada direta.
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $reportSession = Initialize-ToolkitReportSession -ModuleName 'detectar-ip-duplicado'
    }
    else {
        $reportSession = Initialize-ToolkitReportSession -ReportsRoot $OutputPath -ModuleName 'detectar-ip-duplicado'
    }
    $OutputPath = $reportSession.Path
    Write-Verbose "Saida dos relatorios: $OutputPath"

    # === ETAPA 5: geracao dos tres relatorios (TXT, MD, HTML) ============
    # Context agrupa os metadados que aparecem no cabecalho de todos os 3
    # formatos. New-DuplicateIpReport e quem monta e grava os arquivos.
    $context = [pscustomobject]@{
        Timestamp        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Range            = $Range
        Interface        = $Interface
        TotalConsultado  = $ipList.Count
        TotalEncontrado  = $totalOccupied
        TotalOcupados    = $totalOccupied
        TotalLivres      = $totalFree
        TotalDuplicados  = $totalDup
    }

    $paths = New-DuplicateIpReport `
        -Results $results `
        -FreeIPs $freeIps `
        -Context $context `
        -OutputPath $OutputPath

    Write-Verbose ('Relatorios gerados: {0}' -f ($paths -join '; '))

    # Anexa o caminho dos arquivos no primeiro objeto retornado para que quem
    # consumir via pipeline possa listar os arquivos gerados sem adivinhar.
    if ($results.Count -gt 0) {
        $results[0] | Add-Member -MemberType NoteProperty -Name ReportFiles -Value $paths -PassThru | Out-Null
    }

    return $results
}
