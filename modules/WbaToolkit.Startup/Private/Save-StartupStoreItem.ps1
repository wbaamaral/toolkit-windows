function Save-StartupStoreItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Item,
        [string]$BackupPath
    )

    $storePath = Get-StartupStorePath
    if (-not (Test-Path -LiteralPath $storePath)) {
        New-Item -Path $storePath -Force -ErrorAction Stop | Out-Null
    }
    $itemPath = Join-Path $storePath $Item.Id
    New-Item -Path $itemPath -Force -ErrorAction Stop | Out-Null

    $valueKind = if ($Item.ValueKind) { [string]$Item.ValueKind } else { 'String' }

    # Metadados textuais. ValueKind registra o tipo nativo para restauracao fiel.
    $properties = @{
        Id         = $Item.Id
        Name       = $Item.Name
        SourceType = $Item.SourceType
        Scope      = $Item.Scope
        Location   = $Item.Location
        ValueName  = $Item.ValueName
        ValueKind  = $valueKind
        BackupPath = $BackupPath
        DisabledAt = (Get-Date).ToString('o')
    }

    foreach ($key in $properties.Keys) {
        New-ItemProperty -Path $itemPath -Name $key -Value ([string]$properties[$key]) -PropertyType String -Force -ErrorAction Stop | Out-Null
    }

    # Payload (valor de inicializacao). Para Registry, preserva o tipo nativo e o valor
    # bruto (REG_EXPAND_SZ/REG_BINARY/REG_DWORD nao sao convertidos para String).
    if ($Item.SourceType -eq 'Registry' -and $null -ne $Item.RawValue) {
        New-ItemProperty -Path $itemPath -Name 'Command' -Value $Item.RawValue -PropertyType $valueKind -Force -ErrorAction Stop | Out-Null
    }
    else {
        New-ItemProperty -Path $itemPath -Name 'Command' -Value ([string]$Item.Command) -PropertyType String -Force -ErrorAction Stop | Out-Null
    }
}
