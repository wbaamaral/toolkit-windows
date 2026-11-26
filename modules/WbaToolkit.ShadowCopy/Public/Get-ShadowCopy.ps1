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

    $shadows = @(Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue)
    # Win32_ShadowCopy so expoe VolumeName (\\?\Volume{guid}\); a letra vem de Win32_Volume.
    $volumeMap = Get-ShadowVolumeMap

    if ($Volume) {
        $volPath = Resolve-VolumePath -Volume $Volume
        $shadows = @($shadows | Where-Object { $volumeMap[[string]$_.VolumeName] -eq $volPath })
    }

    $shadows | ForEach-Object {
        $volumeName = [string]$_.VolumeName
        [pscustomobject]@{
            ShadowCopyId  = $_.ID
            Volume        = $(if ($volumeMap.ContainsKey($volumeName)) { $volumeMap[$volumeName] } else { $volumeName })
            DeviceObject  = $_.DeviceObject
            CreatedAt     = $_.InstallDate
            State         = $_.State
            Provider      = $_.ProviderID
            ClientAccessible = $_.ClientAccessible
        }
    }
}
