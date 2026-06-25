function Clear-LsaSecret {
    <#
    .SYNOPSIS
        Remove um segredo privado da LSA.

    .DESCRIPTION
        Apaga o segredo privado da LSA sob a chave informada. Usado ao desabilitar o
        autologon para limpar a senha ('DefaultPassword'). Idempotente: ausencia do
        segredo nao e tratada como erro.

    .PARAMETER Name
        Nome da chave do segredo a remover.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    Initialize-LsaInterop
    try {
        [Wba.Interop.LsaSecretManager]::Delete($Name)
    }
    catch {
        Write-Verbose "Clear-LsaSecret: $($_.Exception.Message)"
    }
}
