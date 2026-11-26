function Get-SoftwareLicensingProduct {
    <#
    .SYNOPSIS
        Consulta os produtos de licenciamento do Windows que tem chave instalada.

    .DESCRIPTION
        A classe SoftwareLicensingProduct lista dezenas de SKUs para o ApplicationId do
        Windows; so o produto com PartialProductKey preenchido e o que esta instalado
        (mesmo criterio do slmgr). Sem esse filtro, quem pegava o primeiro item recebia
        uma edicao sem chave e com LicenseStatus 0.
    #>
    [CmdletBinding()]
    param(
        [string]$ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    )

    try {
        $filter = "ApplicationId='$ApplicationId' AND PartialProductKey IS NOT NULL"
        return @(Get-CimInstance -Namespace 'root/cimv2' -ClassName SoftwareLicensingProduct -Filter $filter -ErrorAction Stop)
    }
    catch {
        Write-Verbose "Falha ao consultar SoftwareLicensingProduct: $($_.Exception.Message)"
        return @()
    }
}
