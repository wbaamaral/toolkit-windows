function ConvertFrom-SecureStringPlain {
    <#
    .SYNOPSIS
        Converte um SecureString para texto, apenas em memoria, para gravacao imediata na LSA.

    .DESCRIPTION
        Desprotege um SecureString para String usando marshaling nao gerenciado e libera
        o buffer (ZeroFreeBSTR) logo apos. O texto resultante NUNCA deve ser logado,
        exibido ou persistido em disco/registro: o unico consumidor legitimo e
        Set-LsaSecret, no instante da gravacao do segredo do autologon.

    .PARAMETER Secure
        O SecureString a desproteger.

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][System.Security.SecureString]$Secure
    )

    $bstr = [System.IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
