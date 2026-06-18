function ConvertTo-StoreSizeGB {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Unit
    )

    $num = [double]($Value -replace ',', '.')
    switch ($Unit) {
        'GB'    { return [math]::Round($num, 3) }
        'MB'    { return [math]::Round($num / 1024, 3) }
        'KB'    { return [math]::Round($num / 1048576, 3) }
        default { return [math]::Round($num / 1073741824, 3) }
    }
}
