function Get-StartupDisabledRoot {
    [CmdletBinding()]
    param()

    $base = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    return (Join-Path $base 'WBA\Startup\Disabled')
}
