function Test-ToolkitPropertyPresent {
    <#
    .SYNOPSIS
        Verifica se uma propriedade existe em um objeto, seguro sob Set-StrictMode.

    .DESCRIPTION
        '$obj.PSObject.Properties.Name -contains "x"' lanca PropertyNotFoundException
        sob 'Set-StrictMode -Version Latest' quando $obj tem zero propriedades (o modulo
        inteiro roda sob esse StrictMode). Indexar a colecao por nome
        ('$obj.PSObject.Properties["x"]') e seguro em qualquer caso e e o que esta funcao
        centraliza, para nao repetir a ressalva em cada etapa que le a configuracao.

    .PARAMETER InputObject
    .PARAMETER Name
        Nome da propriedade a verificar.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $false
    }

    return [bool]$InputObject.PSObject.Properties[$Name]
}
