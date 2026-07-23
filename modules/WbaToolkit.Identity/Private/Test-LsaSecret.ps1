function Test-LsaSecret {
    <#
    .SYNOPSIS
        Verifica se um segredo privado da LSA esta definido.

    .DESCRIPTION
        Retorna $true se houver um segredo privado da LSA sob a chave informada,
        sem nunca revelar ou retornar o valor. Usado para reportar se a senha do
        autologon ('DefaultPassword') esta presente.

    .PARAMETER Name
        Nome da chave do segredo a verificar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    Initialize-LsaInterop
    try {
        return [Wba.Interop.LsaSecretManager]::Exists($Name)
    }
    catch {
        Write-Verbose "Test-LsaSecret: $($_.Exception.Message)"
        return $false
    }
}
