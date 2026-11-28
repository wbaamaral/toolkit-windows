function Get-ShadowCopyProtectionStatus {
    <#
    .SYNOPSIS
        Verifica o status da Protecao do Sistema por volume.
    .DESCRIPTION
        Retorna o status (Habilitado/Desabilitado) da Protecao do Sistema
        para cada volume fixo, incluindo espaco alocado e disponivel.
    .OUTPUTS
        PSCustomObject com Volume, DriveLetter, Label, FileSystem, SizeGB, FreeGB, ProtectionEnabled e AllocatedGB.
    #>
    [CmdletBinding()]
    param()

    $volumes = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }

    # A configuracao da Restauracao do Sistema e global, nao por volume.
    $srConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -ErrorAction SilentlyContinue
    $protEnabled = ($srConfig.RPSessionInterval -eq 1) -and ($srConfig.DisableSR -ne 1)

    # Espaco alocado vem de Win32_ShadowStorage: o texto do vssadmin muda com o idioma (ADR 0034).
    $storage = @()
    try { $storage = @(Get-ShadowStorageInfo) }
    catch { Write-Verbose "Nao foi possivel obter o uso de armazenamento de copia de sombra: $($_.Exception.Message)" }

    $results = foreach ($vol in $volumes) {
        $driveLetter = $vol.DriveLetter
        $volPath = "${driveLetter}:\"
        $assoc = @($storage | Where-Object { $_.Volume -eq $volPath }) | Select-Object -First 1

        [pscustomobject]@{
            Volume             = $volPath
            DriveLetter        = $driveLetter
            Label              = $vol.FileSystemLabel
            FileSystem         = $vol.FileSystem
            SizeGB             = [math]::Round($vol.Size / 1GB, 2)
            FreeGB             = [math]::Round($vol.SizeRemaining / 1GB, 2)
            ProtectionEnabled  = $protEnabled
            AllocatedGB        = if ($assoc) { [math]::Round($assoc.AllocatedSpace / 1GB, 2) } else { $null }
        }
    }

    $results
}
