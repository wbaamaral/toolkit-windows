# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxDiskFreeInfo {
    <#
    .SYNOPSIS
        Retorna informacoes de espaco livre do volume identificado pela letra de unidade.

    .DESCRIPTION
        Fronteira isolada e mockavel sobre Get-CimInstance Win32_LogicalDisk. Falha
        de consulta e um cenario esperado (WMI indisponivel, unidade removivel) e
        retorna $null em vez de lancar.

    .PARAMETER DriveLetter
        Letra da unidade no formato 'C:'.

    .OUTPUTS
        Microsoft.Management.Infrastructure.CimInstance ou $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )

    try {
        return Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$DriveLetter'" -ErrorAction Stop
    }
    catch {
        Write-Verbose "Nao foi possivel consultar Win32_LogicalDisk para '$DriveLetter': $($_.Exception.Message)"
        return $null
    }
}
