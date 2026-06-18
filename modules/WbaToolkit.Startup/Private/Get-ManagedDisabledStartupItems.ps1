function Get-ManagedDisabledStartupItems {
    [CmdletBinding()]
    param()

    $storePath = Get-StartupStorePath
    if (-not (Test-Path -LiteralPath $storePath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $storePath -ErrorAction SilentlyContinue | ForEach-Object {
        $item = Get-ItemProperty -LiteralPath $_.PSPath
        ConvertTo-StartupItem `
            -SourceType $item.SourceType `
            -Scope $item.Scope `
            -Location $item.Location `
            -Name $item.Name `
            -ValueName $item.ValueName `
            -Command $item.Command `
            -Enabled $false `
            -ManagedDisabled $true `
            -BackupPath $item.BackupPath
    })
}
