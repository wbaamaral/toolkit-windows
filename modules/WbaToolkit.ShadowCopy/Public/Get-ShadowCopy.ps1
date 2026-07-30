function Get-ShadowCopy {
    <#
    .SYNOPSIS
        Lista shadow copies existentes.
    .DESCRIPTION
        Retorna todos os shadow copies do volume especificado ou de todos os volumes.
    .PARAMETER Volume
        Filtrar por volume (ex: C:). Se omitido, retorna todos.
    .OUTPUTS
        Lista de PSCustomObject com ShadowCopyId, Volume, DeviceObject, CreatedAt, State, Provider.
    #>
    [CmdletBinding()]
    param(
        [string]$Volume
    )

    $shadows = Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue

    if ($Volume) {
        $volPath = Resolve-VolumePath -Volume $Volume
        $shadows = $shadows | Where-Object { $_.Volume -like "$volPath*" }
    }

    $shadows | ForEach-Object {
        [pscustomobject]@{
            ShadowCopyId  = $_.ID
            Volume        = $_.Volume
            DeviceObject  = $_.DeviceObject
            CreatedAt     = $_.InstallDate
            State         = $_.State
            Provider      = $_.ProviderID
            ClientAccessible = $_.ClientAccessible
        }
    }
}
