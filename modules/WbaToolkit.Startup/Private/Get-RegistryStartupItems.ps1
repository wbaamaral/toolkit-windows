function Get-RegistryStartupItems {
    [CmdletBinding()]
    param()

    $locations = @(
        @{ Scope = 'Machine';   Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Scope = 'Machine';   Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ Scope = 'Machine32'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' },
        @{ Scope = 'User';      Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Scope = 'User';      Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    )

    $items = [System.Collections.ArrayList]::new()
    foreach ($location in $locations) {
        if (-not (Test-Path -LiteralPath $location.Path)) {
            continue
        }

        $properties = Get-ItemProperty -LiteralPath $location.Path -ErrorAction SilentlyContinue
        foreach ($property in @($properties.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
            $null = $items.Add((ConvertTo-StartupItem `
                -SourceType 'Registry' `
                -Scope $location.Scope `
                -Location $location.Path `
                -Name $property.Name `
                -ValueName $property.Name `
                -Command ([string]$property.Value) `
                -Enabled $true))
        }
    }

    return @($items)
}
