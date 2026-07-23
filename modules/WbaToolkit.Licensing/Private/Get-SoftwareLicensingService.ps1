function Get-SoftwareLicensingService {
    [CmdletBinding()]
    param()

    try {
        return @(Get-CimInstance -Namespace 'root/cimv2' -ClassName SoftwareLicensingService -ErrorAction Stop)
    }
    catch {
        Write-Verbose "Falha ao consultar SoftwareLicensingService: $($_.Exception.Message)"
        return @()
    }
}
