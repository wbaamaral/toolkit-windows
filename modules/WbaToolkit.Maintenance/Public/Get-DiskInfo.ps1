function Get-DiskInfo {
    <#
    .SYNOPSIS
        Retorna informacoes de espaco em disco da unidade do sistema.

    .DESCRIPTION
        Consulta o disco correspondente ao SystemDrive via WMI e retorna tamanho
        total e espaco livre em gigabytes.

    .EXAMPLE
        Get-DiskInfo

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com DeviceID, TamanhoGB e LivreGB.

    .NOTES
        Autor: wbaamaral
    #>
    [CmdletBinding()]
    param()

    Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" |
        Select-Object DeviceID,
            @{Name = 'TamanhoGB'; Expression = { [math]::Round($_.Size / 1GB, 2) } },
            @{Name = 'LivreGB';   Expression = { [math]::Round($_.FreeSpace / 1GB, 2) } }
}
