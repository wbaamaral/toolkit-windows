function Get-ToolkitPropertyNames {
    <#
    .SYNOPSIS
        Lista os nomes de propriedade de um objeto, seguro sob Set-StrictMode.

    .DESCRIPTION
        '@($obj.PSObject.Properties.Name)' lanca PropertyNotFoundException sob
        'Set-StrictMode -Version Latest' quando $obj tem zero propriedades — o proprio
        '@()' externo nao protege, pois o erro ocorre durante a enumeracao de membro
        antes do array ser montado. Canalizar pelo pipeline evita a enumeracao de
        membro direta e e seguro em qualquer caso.

    .PARAMETER InputObject

    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    return @($InputObject.PSObject.Properties | ForEach-Object Name)
}
