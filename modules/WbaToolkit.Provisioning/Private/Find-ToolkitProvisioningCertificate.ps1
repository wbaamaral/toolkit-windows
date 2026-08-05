function Find-ToolkitProvisioningCertificate {
    <#
    .SYNOPSIS
        Localiza um certificado instalado por thumbprint, em um repositorio declarado.

    .PARAMETER Thumbprint
    .PARAMETER Store
        Caminho de provider no formato 'LocalMachine\My'. Padrao: 'LocalMachine\My'.

    .OUTPUTS
        Certificado (System.Security.Cryptography.X509Certificates.X509Certificate2) ou $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Thumbprint,

        [string]$Store = 'LocalMachine\My'
    )

    $psPath = "Cert:\$Store"
    if (-not (Test-Path -LiteralPath $psPath)) {
        return $null
    }

    Get-ChildItem -LiteralPath $psPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $Thumbprint.ToUpperInvariant() } |
        Select-Object -First 1
}
