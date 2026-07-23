function Get-AutologonStorePath {
    [CmdletBinding()]
    param()

    return 'HKLM:\SOFTWARE\WBA\WindowsToolkit\Autologon\Backup'
}
