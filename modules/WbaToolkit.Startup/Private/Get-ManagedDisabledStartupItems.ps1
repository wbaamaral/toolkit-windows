function Get-ManagedDisabledStartupItems {
    [CmdletBinding()]
    param()

    $storePath = Get-StartupStorePath
    if (-not (Test-Path -LiteralPath $storePath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $storePath -ErrorAction SilentlyContinue | ForEach-Object {
        # Um item de store malformado (ex.: gravado por versao anterior) nao deve
        # derrubar toda a enumeracao e tornar os demais itens irrecuperaveis.
        try {
            $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop

            $valueKind = if ($item.PSObject.Properties['ValueKind']) { [string]$item.ValueKind } else { 'String' }
            $rawValue  = $item.Command

            $display = if ($valueKind -eq 'Binary') {
                '[binario]'
            }
            elseif ($valueKind -eq 'MultiString') {
                ($rawValue -join ' | ')
            }
            else {
                [string]$rawValue
            }

            ConvertTo-StartupItem `
                -SourceType $item.SourceType `
                -Scope $item.Scope `
                -Location $item.Location `
                -Name $item.Name `
                -ValueName $item.ValueName `
                -Command $display `
                -ValueKind $valueKind `
                -RawValue $rawValue `
                -Enabled $false `
                -ManagedDisabled $true `
                -BackupPath $item.BackupPath
        }
        catch {
            Write-Warning "Item de inicializacao desabilitado ilegivel no store ('$($_.PSChildName)'): $($_.Exception.Message)"
        }
    })
}
