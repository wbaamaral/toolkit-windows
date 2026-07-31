function Get-BackupConfigurationInternal {
    [CmdletBinding()]
    param()

    $configDir = Join-Path $PSScriptRoot '..\..\..'
    $candidates = @(
        (Join-Path $env:ProgramData 'WBA\WindowsToolkit\config-backup.json'),
        (Join-Path $PSScriptRoot '..\..\..\config-backup.json')
    )

    foreach ($path in $candidates) {
        $resolved = [System.IO.Path]::GetFullPath($path)
        if (Test-Path $resolved) { return $resolved }
    }

    return $null
}
