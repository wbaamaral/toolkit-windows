function ConvertTo-StoreSizeGB {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Unit
    )

    # DISM e forcado com /English (ver Get-ComponentStoreInfo): separador decimal '.'
    # e milhar ','. Removemos o milhar e parseamos com InvariantCulture para evitar
    # ambiguidade de cultura (pt-BR usa ',' como decimal).
    $normalizado = ($Value -replace '\s', '') -replace ',', ''
    $num = 0.0
    if (-not [double]::TryParse(
            $normalizado,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$num)) {
        return $null
    }
    switch ($Unit) {
        'GB'    { return [math]::Round($num, 3) }
        'MB'    { return [math]::Round($num / 1024, 3) }
        'KB'    { return [math]::Round($num / 1048576, 3) }
        default { return [math]::Round($num / 1073741824, 3) }
    }
}
