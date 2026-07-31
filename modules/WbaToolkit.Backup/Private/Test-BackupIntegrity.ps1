function Test-BackupIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath
    )

    if (-not (Test-Path $BackupPath)) { return $false }

    $metaPath = Join-Path $BackupPath 'metadados.json'
    if (-not (Test-Path $metaPath)) { return $false }

    try {
        $meta = Get-Content -Path $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $meta.BackupPath) { return $false }

        $sourcePaths = $meta.SourcePaths | ForEach-Object {
            if (Test-Path $_) { $_ }
        }

        if (-not $sourcePaths -or $sourcePaths.Count -eq 0) { return $false }

        return $true
    } catch {
        return $false
    }
}
