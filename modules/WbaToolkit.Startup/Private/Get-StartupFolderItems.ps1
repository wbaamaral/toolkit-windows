function Get-StartupFolderItems {
    [CmdletBinding()]
    param()

    $folders = @(
        @{ Scope = 'User';    Path = [Environment]::GetFolderPath('Startup') },
        @{ Scope = 'Machine'; Path = [Environment]::GetFolderPath('CommonStartup') }
    )

    $items = [System.Collections.ArrayList]::new()
    foreach ($folder in $folders) {
        if ([string]::IsNullOrWhiteSpace($folder.Path) -or -not (Test-Path -LiteralPath $folder.Path)) {
            continue
        }

        foreach ($file in @(Get-ChildItem -LiteralPath $folder.Path -File -ErrorAction SilentlyContinue)) {
            $null = $items.Add((ConvertTo-StartupItem `
                -SourceType 'StartupFolder' `
                -Scope $folder.Scope `
                -Location $folder.Path `
                -Name $file.Name `
                -ValueName $file.Name `
                -Command $file.FullName `
                -Enabled $true))
        }
    }

    return @($items)
}
