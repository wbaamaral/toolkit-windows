function Get-ShadowStorageInfo {
    # Associacoes de shadow storage lidas de Win32_ShadowStorage (ADR 0034): tamanhos em bytes e volumes por
    # DeviceID. A saida do vssadmin e traduzida ("Nenhum item...", "Espaco usado...") e nao serve para parse.
    [CmdletBinding()]
    param()

    $map = Get-ShadowVolumeMap
    foreach ($storage in @(Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop)) {
        $volumeId = [string]$storage.Volume.DeviceID
        $diffId = [string]$storage.DiffVolume.DeviceID
        [pscustomobject]@{
            Volume             = if ($map.ContainsKey($volumeId)) { $map[$volumeId] } else { $volumeId }
            VolumeDeviceId     = $volumeId
            DiffVolume         = if ($map.ContainsKey($diffId)) { $map[$diffId] } else { $diffId }
            DiffVolumeDeviceId = $diffId
            UsedSpace          = [uint64]$storage.UsedSpace
            AllocatedSpace     = [uint64]$storage.AllocatedSpace
            MaxSpace           = [uint64]$storage.MaxSpace
        }
    }
}
