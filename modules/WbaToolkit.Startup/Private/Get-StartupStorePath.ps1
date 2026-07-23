function Get-StartupStorePath {
    [CmdletBinding()]
    param()

    return 'HKLM:\SOFTWARE\WBA\WindowsToolkit\Startup\Disabled'
}
