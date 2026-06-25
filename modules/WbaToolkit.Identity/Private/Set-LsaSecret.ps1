function Set-LsaSecret {
    <#
    .SYNOPSIS
        Armazena um segredo privado da LSA.

    .DESCRIPTION
        Grava o valor informado como segredo privado da LSA, sob a chave indicada.
        Para o autologon, a chave e 'DefaultPassword'. O valor nunca e gravado em
        texto claro no registro.

    .PARAMETER Name
        Nome da chave do segredo (ex.: 'DefaultPassword').

    .PARAMETER Value
        Valor em texto a armazenar. Mantido apenas em memoria durante a chamada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    Initialize-LsaInterop
    [Wba.Interop.LsaSecretManager]::Store($Name, $Value)
}
