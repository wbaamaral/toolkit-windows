function Get-ShadowVolumeMap {
    <#
    .SYNOPSIS
        Mapeia o caminho GUID dos volumes (\\?\Volume{...}\) para a letra de unidade.

    .DESCRIPTION
        Win32_ShadowCopy identifica o volume de origem apenas por VolumeName, no formato
        \\?\Volume{guid}\; nao existe propriedade com a letra da unidade. Win32_Volume
        liga DeviceID (mesmo formato) a Name ('C:\'). Volumes sem letra mapeiam para o
        proprio caminho GUID.

    .OUTPUTS
        System.Collections.Hashtable — chave DeviceID (case-insensitive), valor Name.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $map = @{}
    foreach ($vol in @(Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop)) {
        if ($vol.DeviceID) {
            $map[[string]$vol.DeviceID] = if ($vol.Name) { [string]$vol.Name } else { [string]$vol.DeviceID }
        }
    }
    return $map
}
