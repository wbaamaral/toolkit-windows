function Get-ShadowCopyStorage {
    <#
    .SYNOPSIS
        Retorna informacoes de uso do shadow storage por volume.
    .DESCRIPTION
        Usa vssadmin para listar o uso de espaco do shadow storage.
    .PARAMETER Volume
        Volume alvo (ex: C:). Se omitido, retorna todos.
    .OUTPUTS
        PSCustomObject com Volume, UsedSpace, AllocatedSpace, MaxSpace.
    #>
    [CmdletBinding()]
    param(
        [string]$Volume
    )

    if ($Volume) {
        $volPath = Resolve-VolumePath -Volume $Volume
        $result = Invoke-VssAdmin -Arguments @('list', 'shadowstorage', "/for=${volPath}")
    } else {
        $result = Invoke-VssAdmin -Arguments @('list', 'shadowstorage')
    }

    if ($result.ExitCode -ne 0) {
        return @()
    }

    if ($result.Output -match 'Nenhum item|No items|No shadow copy storage') {
        return @()
    }

    $parsed = ConvertFrom-VssAdminOutput -Text $result.Output

    foreach ($item in $parsed.Storage) {
        [pscustomobject]@{
            Volume            = $item.Volume
            ShadowCopyVolume  = $item.ShadowCopyStorage
            UsedSpace         = $item.UsedSpace
            AllocatedSpace    = $item.AllocatedSpace
            MaximumSpace      = $item.MaximumSpace
        }
    }
}
