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
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        $srState = Get-ItemProperty -Path $regPath -Name "RPSessionInterval" -ErrorAction SilentlyContinue

        $protEnabled = $false
        $scope = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\VolSnapShot\Parameters" -ErrorAction SilentlyContinue

        try {
            $srConfig = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        } catch { }

        $regKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SRP\Volume\Volume{$(Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue | ForEach-Object { $_.Path.Replace('\', '').Replace(':', '') })}"
        if (Test-Path $regKey) {
            $protEnabled = $true
        } else {
            $protCheck = & Enable-ComputerRestore -Drive "${driveLetter}:\" 2>&1
            if ($protCheck -notmatch 'desabilitado|disabled|not supported') {
                $protEnabled = $true
            }
        }

        $storageInfo = $null
        try {
            $vssResult = Invoke-VssAdmin -Arguments @('list', 'shadowstorage', "/for=${driveLetter}:\")
            if ($vssResult.ExitCode -eq 0 -and $vssResult.Output -match 'Allocated Space:\s*(.+?)\s*GB') {
                $storageInfo = [pscustomobject]@{
                    AllocatedGB = [double]$Matches[1]
                }
            }
        } catch { }

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
