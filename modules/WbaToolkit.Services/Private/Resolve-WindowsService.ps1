function Resolve-WindowsService {
    <#
    .SYNOPSIS
        Valida se um servico Windows existe e retorna seu objeto.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue

    if (-not $service) {
        return [pscustomobject]@{
            Exists  = $false
            Service = $null
            Message = "Servico '$Name' nao encontrado."
        }
    }

    [pscustomobject]@{
        Exists  = $true
        Service = $service
        Message = ''
    }
}
