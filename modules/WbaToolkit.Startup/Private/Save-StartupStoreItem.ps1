function Save-StartupStoreItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Item,
        [string]$BackupPath
    )

    $storePath = Get-StartupStorePath
    New-Item -Path $storePath -Force | Out-Null
    $itemPath = Join-Path $storePath $Item.Id
    New-Item -Path $itemPath -Force | Out-Null

    $properties = @{
        Id         = $Item.Id
        Name       = $Item.Name
        SourceType = $Item.SourceType
        Scope      = $Item.Scope
        Location   = $Item.Location
        ValueName  = $Item.ValueName
        Command    = $Item.Command
        BackupPath = $BackupPath
        DisabledAt = (Get-Date).ToString('o')
    }

    foreach ($key in $properties.Keys) {
        New-ItemProperty -Path $itemPath -Name $key -Value ([string]$properties[$key]) -PropertyType String -Force | Out-Null
    }
}
