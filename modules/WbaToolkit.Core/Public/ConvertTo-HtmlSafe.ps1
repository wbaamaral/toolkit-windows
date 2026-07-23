function ConvertTo-HtmlSafe {
    <#
    .SYNOPSIS
        Escapa texto para uso seguro em HTML.

    .DESCRIPTION
        Converte caracteres especiais para entidades HTML e retorna um valor padronizado
        para relatorios HTML.

    .PARAMETER Value
        Valor a ser escapado.

    .PARAMETER Default
        Valor retornado quando a entrada for nula ou vazia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $false)]
        [string]$Default = '<span class="text-gray-500">&mdash;</span>'
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
        return $Default
    }

    return ([string]$Value) -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}
