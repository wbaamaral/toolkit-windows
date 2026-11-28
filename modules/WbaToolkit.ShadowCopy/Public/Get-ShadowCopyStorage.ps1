function Get-ShadowCopyStorage {
    <#
    .SYNOPSIS
        Retorna informacoes de uso do shadow storage por volume.
    .DESCRIPTION
        Le as associacoes de Win32_ShadowStorage, que independem do idioma do Windows (ADR 0034).
    .PARAMETER Volume
        Volume alvo (ex: C:). Se omitido, retorna todos.
    .OUTPUTS
        PSCustomObject com Volume, ShadowCopyVolume, UsedSpace, AllocatedSpace e MaximumSpace (texto) e
        UsedSpaceBytes, AllocatedSpaceBytes e MaxSpaceBytes. MaxSpaceBytes nulo significa sem limite.
    #>
    [CmdletBinding()]
    param(
        [string]$Volume
    )

    $volPath = if ($Volume) { Resolve-VolumePath -Volume $Volume } else { $null }

    try {
        $items = @(Get-ShadowStorageInfo)
    } catch {
        Write-Warning "Nao foi possivel consultar o shadow storage (Win32_ShadowStorage): $($_.Exception.Message)"
        return @()
    }

    # MaxSpace com o maior UInt64 e o "UNBOUNDED" do vssadmin.
    $toText = {
        param([uint64]$Bytes, [switch]$Max)
        if ($Max -and $Bytes -eq [uint64]::MaxValue) { return 'Sem limite' }
        '{0:N2} GB' -f ($Bytes / 1GB)
    }

    foreach ($item in $items) {
        if ($volPath -and $item.Volume -ne $volPath) { continue }
        [pscustomobject]@{
            Volume              = $item.Volume
            ShadowCopyVolume    = $item.DiffVolume
            UsedSpace           = & $toText $item.UsedSpace
            AllocatedSpace      = & $toText $item.AllocatedSpace
            MaximumSpace        = & $toText $item.MaxSpace -Max
            UsedSpaceBytes      = $item.UsedSpace
            AllocatedSpaceBytes = $item.AllocatedSpace
            MaxSpaceBytes       = if ($item.MaxSpace -eq [uint64]::MaxValue) { $null } else { $item.MaxSpace }
        }
    }
}
