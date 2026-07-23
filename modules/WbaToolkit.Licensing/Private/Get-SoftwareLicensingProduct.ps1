function Get-SoftwareLicensingProduct {
    [CmdletBinding()]
    param(
        [string]$ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    )

    try {
        $filter = "ApplicationId='$ApplicationId'"
        return @(Get-CimInstance -Namespace 'root/cimv2' -ClassName SoftwareLicensingProduct -Filter $filter -ErrorAction Stop)
    }
    catch {
        Write-Verbose "Falha ao consultar SoftwareLicensingProduct: $($_.Exception.Message)"
        return @()
    }
}
