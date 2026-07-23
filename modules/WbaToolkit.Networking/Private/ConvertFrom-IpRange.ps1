function ConvertFrom-IpRange {
    <#
    .SYNOPSIS
        Expande uma faixa de IPv4 em uma lista de enderecos validos.

    .DESCRIPTION
        Aceita tres formatos de entrada e retorna a enumeracao completa de todos os
        enderecos IP uteis dentro da faixa informada:

          - CIDR:                  192.168.1.0/24
          - Intervalo completo:    192.168.1.1-192.168.1.254
          - Intervalo compacto:    192.168.1.10-50  (mesmo /24, so o octeto final varia)
          - IP unico:              192.168.1.5

        A expansao usa aritmetica de inteiros de 32 bits (uint32) para suportar qualquer
        mascara de /8 a /30. Faixas acima de /16 (mais de 65536 enderecos) geram aviso
        de performance, porque uma varredura ARP com ping assincrono vai demorar.

    .PARAMETER Range
        Faixa no formato CIDR, intervalo ou IP unico. Nao pode misturar formatos
        (ex.: "192.168.1.0/24-10" e rejeitado).

    .EXAMPLE
        ConvertFrom-IpRange -Range '192.168.1.0/24'

    .EXAMPLE
        ConvertFrom-IpRange -Range '192.168.1.10-50'

    .EXAMPLE
        ConvertFrom-IpRange -Range '192.168.1.1-192.168.1.254'

    .NOTES
        Privada do modulo WbaToolkit.Networking. Retorna apenas IPs uteis (host bits
        nao todos zero nem todos um dentro da rede).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Range
    )

    # --- Helpers internos ---------------------------------------------------

    # Converte um IP "A.B.C.D" em inteiro sem sinal de 32 bits (big-endian network order).
    function ConvertTo-IpAddressInt {
        param([string]$IpAddress)
        $octets = $IpAddress.Split('.')
        if ($octets.Count -ne 4) { return $null }
        # Use UInt64 during the shifts. PowerShell otherwise promotes the
        # intermediate value to Int32 and IPs whose first octet is >= 128
        # become negative before the final UInt32 cast.
        [uint64]$result = 0
        foreach ($oct in $octets) {
            $n = 0
            if (-not [int]::TryParse($oct, [ref]$n)) { return $null }
            if ($n -lt 0 -or $n -gt 255) { return $null }
            $result = ($result -shl 8) -bor [uint64]$n
        }
        return [uint32]$result
    }

    # Inverso do helper acima: uint32 -> string "A.B.C.D".
    function ConvertFrom-IpAddressInt {
        param([uint32]$Value)
        $b1 = ($Value -shr 24) -band 0xFF
        $b2 = ($Value -shr 16) -band 0xFF
        $b3 = ($Value -shr 8)  -band 0xFF
        $b4 = $Value           -band 0xFF
        return (($b1, $b2, $b3, $b4) -join '.')
    }

    # Valida se a string e um IPv4 bem-formado usando o parser nativo do .NET.
    function Test-ValidIpv4 {
        param([string]$IpAddress)
        $addr = $null
        return ([System.Net.IPAddress]::TryParse($IpAddress, [ref]$addr) -and `
               ($addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork))
    }

    # --- Reconhecimento de formato ------------------------------------------

    # CIDR ("192.168.1.0/24") usa caractere '/'. Variaveis de parsing.
    $cidrMatch = [regex]::Match($Range, '^(?<ip>(\d{1,3}\.){3}\d{1,3})/(?<mask>\d{1,2})$')
    # Intervalo ("a.b.c.d-e.f.g.h" ou "a.b.c.d-XX") usa traco separando inicio e fim.
    $rangeMatch = [regex]::Match($Range, '^(?<start>(\d{1,3}\.){3}\d{1,3})-(?<end>(\d{1,3}\.){3}\d{1,3}|\d{1,3})$')

    if ($cidrMatch.Success) {

        # Caso 1: CIDR ----------------------------------------------------------
        # Extrai IP e mascara (1..32). Converte para inteiros e aplica bitwise para
        # descobrir endereco de rede e broadcast; enumera todos os hosts entre eles.

        $ipStr   = $cidrMatch.Groups['ip'].Value
        $maskLen = [int]$cidrMatch.Groups['mask'].Value

        if ($maskLen -lt 1 -or $maskLen -gt 32) {
            throw "Mascara CIDR invalida: $Range (mascara deve estar entre 1 e 32)."
        }
        if (-not (Test-ValidIpv4 -IpAddress $ipStr)) {
            throw "IP invalido na faixa CIDR: $Range"
        }

        $ipInt   = [uint32](ConvertTo-IpAddressInt -IpAddress $ipStr)
        $maskInt = if ($maskLen -eq 0) { [uint32]0 } else { [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $maskLen)) }
        $networkInt    = $ipInt  -band $maskInt
        $broadcastInt  = $networkInt -bor (-bnot $maskInt -band 0xFFFFFFFF)

        # /31 e /32 sao especiais: para /31 devolvemos os dois enderecos (p2p);
        # para /32, somente o proprio IP. Caso contrario, descartamos rede e broadcast.
        if ($maskLen -eq 32) {
            $startInt = $networkInt
            $endInt   = $networkInt
        } elseif ($maskLen -eq 31) {
            $startInt = $networkInt
            $endInt   = $broadcastInt
        } else {
            $startInt = $networkInt + 1
            $endInt   = $broadcastInt - 1
        }
    }
    elseif ($rangeMatch.Success) {

        # Caso 2: Intervalo (completo ou compacto) ------------------------------
        # Para formato compacto ("192.168.1.10-50") Montamos o IP final trocando
        # so o ultimo octeto. Para formato completo, ambos os lados ja sao IPs.

        $startStr = $rangeMatch.Groups['start'].Value
        $endStr   = $rangeMatch.Groups['end'].Value

        if (-not (Test-ValidIpv4 -IpAddress $startStr)) {
            throw "IP inicial invalido: $Range"
        }

        $startInt = [uint32](ConvertTo-IpAddressInt -IpAddress $startStr)

        # Se o 'end' e um IP completo, converte direto. Se sao apenas 1-3 digitos,
        # presume intervalo compacto no mesmo /24: troca o ultimo octeto do inicio.
        if ($endStr -match '^(\d{1,3}\.){3}\d{1,3}$') {
            if (-not (Test-ValidIpv4 -IpAddress $endStr)) {
                throw "IP final invalido: $Range"
            }
            $endInt = [uint32](ConvertTo-IpAddressInt -IpAddress $endStr)
        } else {
            # Intervalo compacto: preserva os tres primeiros octetos do inicio
            # e substitui apenas o quarto. Valida faixa 0..255.
            $lastOct = [int]$endStr
            if ($lastOct -lt 0 -or $lastOct -gt 255) {
                throw "Ultimo octeto fora da faixa 0-255 no intervalo compacto: $Range"
            }
            $prefix  = ($startStr.Split('.')[0..2]) -join '.'
            $endFull = "$prefix.$lastOct"
            $endInt  = [uint32](ConvertTo-IpAddressInt -IpAddress $endFull)
        }
    }
    elseif (Test-ValidIpv4 -IpAddress $Range) {

        # Caso 3: IP unico -----------------------------------------------------
        $startInt = [uint32](ConvertTo-IpAddressInt -IpAddress $Range)
        $endInt   = $startInt
    }
    else {
        # Formato nao reconhecido em nenhum dos casos acima. Evita silencio.
        throw "Formato de faixa nao reconhecido: $Range (use CIDR, intervalo ou IP unico)."
    }

    # --- Validacao de ordem e tamanho --------------------------------------

    if ($startInt -gt $endInt) {
        throw "Inicio da faixa maior que o fim: $Range"
    }

    $total = [long]$endInt - [long]$startInt + 1

    # Acima de /16 (65536 enderecos) a varredura demora demais; alerta ao operador.
    if ($total -gt 65536) {
        Write-Warning "Faixa de $total enderecos: a varredura ARP pode demorar varios minutos."
    }

    # --- Enumeracao --------------------------------------------------------
    # Converte de volta para string "A.B.C.D" um a um. Nunca emite os dois
    # enderecos reservados de rede/broadcast no modo CIDR (ja descartados acima).

    $ips = New-Object System.Collections.Generic.List[string]
    for ($i = [long]$startInt; $i -le [long]$endInt; $i++) {
        $ips.Add((ConvertFrom-IpAddressInt -Value ([uint32]$i)))
    }

    # Preserve the array shape when there is only one host. Without
    # -NoEnumerate PowerShell unwraps the single string and callers indexing
    # [0] receive its first character instead of the IP address.
    Write-Output -NoEnumerate $ips.ToArray()
}
