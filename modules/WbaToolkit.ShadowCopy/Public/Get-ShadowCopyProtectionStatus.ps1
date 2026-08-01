function Get-ShadowCopyProtectionStatus {
    <#
    .SYNOPSIS
        Verifica o status da Protecao do Sistema por volume.
    .DESCRIPTION
        Retorna o status (Habilitado/Desabilitado) da Protecao do Sistema
        para cada volume fixo, incluindo espaco alocado e disponivel.
    .OUTPUTS
        PSCustomObject com Volume, ProtectionEnabled, UsedSpaceBytes, AllocatedSpaceBytes, MaxSpaceBytes.
    #>
    [CmdletBinding()]
    param()

    $volumes = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }

    $results = foreach ($vol in $volumes) {
        $driveLetter = $vol.DriveLetter

        $srConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -ErrorAction SilentlyContinue
        $protEnabled = ($srConfig.RPSessionInterval -eq 1) -and ($srConfig.DisableSR -ne 1)

        $storageInfo = $null
        try {
            $vssResult = Invoke-VssAdmin -Arguments @('list', 'shadowstorage', "/for=${driveLetter}:\")
            if ($vssResult.ExitCode -eq 0 -and $vssResult.Output -match 'Allocated Space:\s*(.+?)\s*GB') {
                $storageInfo = [pscustomobject]@{
                    AllocatedGB = [double]$Matches[1]
                }
            }
        } catch { Write-Verbose "Nao foi possivel obter o uso de armazenamento de copia de sombra em ${driveLetter}: $($_.Exception.Message)" }

        [pscustomobject]@{
            Volume             = "${driveLetter}:\"
            DriveLetter        = $driveLetter
            Label              = $vol.FileSystemLabel
            FileSystem         = $vol.FileSystem
            SizeGB             = [math]::Round($vol.Size / 1GB, 2)
            FreeGB             = [math]::Round($vol.SizeRemaining / 1GB, 2)
            ProtectionEnabled  = $protEnabled
            AllocatedGB        = if ($storageInfo) { $storageInfo.AllocatedGB } else { $null }
        }
    }

    $results
}
