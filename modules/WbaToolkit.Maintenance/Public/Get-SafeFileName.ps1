#Requires -Version 5.1
<#
.SYNOPSIS
    Gera um nome de arquivo/diretório seguro e curto o bastante, preservando
    o máximo de legibilidade possível.

.DESCRIPTION
    Remove caracteres inválidos para nomes no Windows (<>:"/\|?*). Se o nome
    já couber em -MaxLength, é devolvido sem outra alteração.

    Quando precisa encurtar, tenta em ordem crescente de agressividade -- só
    avança para o próximo nível se o anterior não coube:

      1. CamelCase: remove espaços/hífens/underscores e acentos, mantendo
         cada palavra capitalizada e concatenada sem separador. O nome
         continua reconhecível (ex. "1 - CONTRATO - MENSALIDADES - EMITIR
         ATE DIA 10" vira "1ContratoMensalidadesEmitirAteDia10").
      2. Abreviação: com o CamelCase ainda não sendo suficiente, cada
         palavra (com 2+ palavras) é cortada em até 4 letras (ex.
         "ContratoMensalidadesEmitir" vira "ContMensEmit").
      3. Hash: último recurso (nome de uma palavra só ininterrupta, ou
         ainda longo demais mesmo abreviado) -- trunca e acrescenta um
         hash SHA-256 curto para garantir tamanho e unicidade.

    A extensão do arquivo (se houver) é preservada através dos níveis 1 e 2.

.PARAMETER Name
    Nome original do arquivo ou diretório.

.PARAMETER MaxLength
    Comprimento máximo permitido para o nome. Padrão: 255 (limite de um componente de caminho no NTFS).

.EXAMPLE
    Get-SafeFileName -Name 'arquivo<inválido>.txt'
    # Retorna: 'arquivoinválido.txt'

.EXAMPLE
    Get-SafeFileName -Name '1 - CONTRATO - MENSALIDADES - EMITIR ATE DIA 10' -MaxLength 30
    # Retorna: 'ContMensEmitAteDia10' (CamelCase nao coube em 30, abreviacao coube)

.OUTPUTS
    System.String
    Nome seguro para o arquivo, sem caracteres inválidos e dentro do limite.
#>
function Get-SafeFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [int]$MaxLength = 255
    )

    function local:Remove-DiacriticoLocal {
        param([string]$Texto)
        $normalizado = $Texto.Normalize([System.Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $normalizado.ToCharArray()) {
            if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($ch)
            }
        }
        return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
    }

    function local:ConvertTo-PalavraCamelLocal {
        param([string]$Palavra)
        $semAcento = Remove-DiacriticoLocal $Palavra
        if ($semAcento.Length -le 1) { return $semAcento.ToUpperInvariant() }
        return $semAcento.Substring(0, 1).ToUpperInvariant() + $semAcento.Substring(1).ToLowerInvariant()
    }

    # Remove caracteres inválidos, incluindo os de controle (0x00-0x1F).
    $validChars = $Name -replace '[<>:"/\\|?*\x00-\x1F]', ''

    # Remover espaços e pontos no final: o Windows os descarta ao criar o item, e o nome
    # gravado deixaria de corresponder ao proposto.
    $validChars = $validChars.TrimEnd(' ', '.')

    # Se o nome for vazio ou apenas espaços, dar um nome padrão
    if ([string]::IsNullOrWhiteSpace($validChars)) {
        $validChars = "arquivo_sem_nome"
    }

    # Nomes reservados do Windows (CON, PRN, AUX, NUL, COM1-9, LPT1-9), com ou sem
    # extensao, nao podem ser criados: recebem '_' no fim da base.
    $evitarReservado = {
        param([string]$Nome)
        $ponto = $Nome.IndexOf('.')
        $base = if ($ponto -ge 0) { $Nome.Substring(0, $ponto) } else { $Nome }
        if ($base -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            if ($ponto -ge 0) { return $base + '_' + $Nome.Substring($ponto) }
            return $Nome + '_'
        }
        return $Nome
    }

    if ($validChars.Length -le $MaxLength) {
        return (& $evitarReservado $validChars)
    }

    # Preservar a extensao (se houver) atraves dos niveis 1 e 2.
    $extensao = [System.IO.Path]::GetExtension($validChars)
    $baseNome = if ($extensao) { $validChars.Substring(0, $validChars.Length - $extensao.Length) } else { $validChars }
    $palavras = @($baseNome -split '[\s\-_–—]+' | Where-Object { $_ -ne '' })

    # Nivel 1: CamelCase -- remove espacos/separadores e acentos, mantendo o
    # nome reconhecivel em vez de ja partir para hash.
    $camel = if ($palavras.Count -gt 0) {
        ($palavras | ForEach-Object { ConvertTo-PalavraCamelLocal $_ }) -join ''
    }
    else {
        Remove-DiacriticoLocal $baseNome
    }
    $candidatoCamel = "$camel$extensao"
    if ($candidatoCamel.Length -le $MaxLength) {
        return (& $evitarReservado $candidatoCamel)
    }

    # Nivel 2: abreviar cada palavra em ate 4 letras -- so faz sentido com
    # 2+ palavras (abreviar uma unica palavra ininterrupta destruiria a
    # unicidade sem ganho real; nesse caso pula direto para o hash).
    if ($palavras.Count -gt 1) {
        $abreviado = ($palavras | ForEach-Object {
            $p = ConvertTo-PalavraCamelLocal $_
            if ($p.Length -gt 4) { $p.Substring(0, 4) } else { $p }
        }) -join ''
        $candidatoAbreviado = "$abreviado$extensao"
        if ($candidatoAbreviado.Length -le $MaxLength) {
            return (& $evitarReservado $candidatoAbreviado)
        }
    }

    # Nivel 3: hash-suffix (ultimo recurso -- garante tamanho e unicidade).
    # Get-FileHash exige caminho de arquivo existente; aqui o hash e calculado
    # diretamente sobre a string do nome original via SHA256 (sem depender de
    # arquivo).
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Name))
    $hashShort = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 8)
    $baseTruncado = $validChars.Substring(0, [Math]::Max(0, ($MaxLength - 10)))
    return "$baseTruncado-$hashShort"
}
