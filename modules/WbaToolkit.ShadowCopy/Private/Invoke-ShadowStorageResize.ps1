function Invoke-ShadowStorageResize {
    # vssadmin resize shadowstorage exige /for, /on e /maxsize. O /on e o volume que guarda as copias:
    # usa o da associacao existente e, sem associacao, o proprio volume. O resultado vale pelo ExitCode,
    # que nao depende do idioma.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumePath,

        [Parameter(Mandatory)]
        [string]$MaxSize
    )

    $onVolume = $VolumePath
    try {
        $association = @(Get-ShadowStorageInfo | Where-Object { $_.Volume -eq $VolumePath }) | Select-Object -First 1
        if ($association -and $association.DiffVolume) { $onVolume = $association.DiffVolume }
    } catch {
        Write-Verbose "Associacao de shadow storage de ${VolumePath} indisponivel; usando o proprio volume: $($_.Exception.Message)"
    }

    Invoke-VssAdmin -Arguments @('resize', 'shadowstorage', "/for=$VolumePath", "/on=$onVolume", "/maxsize=$MaxSize")
}
