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
    Comprimento máximo permitido para o nome. Padrão: 259 (limite do Windows).

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
        [int]$MaxLength = 259
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

    # Remove caracteres inválidos
    $validChars = $Name -replace '[<>:"/\\|?*]', ''

    # Se o nome for vazio ou apenas espaços, dar um nome padrão
    if ([string]::IsNullOrWhiteSpace($validChars)) {
        $validChars = "arquivo_sem_nome"
    }

    # Remover espaços no final
    $validChars = $validChars.TrimEnd()

    if ($validChars.Length -le $MaxLength) {
        return $validChars
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
        return $candidatoCamel
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
            return $candidatoAbreviado
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
