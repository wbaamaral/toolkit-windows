function ConvertTo-ToolkitNormalizedMacAddress {
    <#
    .SYNOPSIS
        Normaliza um endereco MAC para comparacao estavel.

    .DESCRIPTION
        Remove separadores (':', '-', espaco) e converte para maiusculas, de forma que
        '00-50-56-96-1D-27', '00:50:56:96:1d:27' e '005056961D27' comparem iguais.

    .PARAMETER MacAddress
        Endereco MAC em qualquer formatacao comum.

    .OUTPUTS
        System.String — 12 caracteres hexadecimais em maiuscula, ou string vazia se invalido.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$MacAddress
    )

    $normalized = ($MacAddress -replace '[:\-\s]', '').ToUpperInvariant()

    if ($normalized -notmatch '^[0-9A-F]{12}$') {
        return ''
    }

    return $normalized
}
