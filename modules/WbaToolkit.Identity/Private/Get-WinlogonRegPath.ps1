function Get-WinlogonRegPath {
    [CmdletBinding()]
    param()

    return 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
}
