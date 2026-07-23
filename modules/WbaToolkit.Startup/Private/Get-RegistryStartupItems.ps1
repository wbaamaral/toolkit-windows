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

        # Abrimos a chave para obter o tipo nativo (GetValueKind) e o valor bruto
        # sem expandir variaveis de ambiente. Isso preserva REG_EXPAND_SZ/REG_BINARY,
        # que seriam corrompidos se lidos apenas como string.
        $regKey = Get-Item -LiteralPath $location.Path -ErrorAction SilentlyContinue
        if (-not $regKey) { continue }

        foreach ($name in $regKey.GetValueNames()) {
            if ([string]::IsNullOrEmpty($name)) { continue }  # valor padrao da chave

            $kind = $regKey.GetValueKind($name)
            $rawValue = $regKey.GetValue(
                $name, $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

            $display = if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) {
                '[binario]'
            }
            elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) {
                ($rawValue -join ' | ')
            }
            else {
                [string]$rawValue
            }

            $null = $items.Add((ConvertTo-StartupItem `
                -SourceType 'Registry' `
                -Scope $location.Scope `
                -Location $location.Path `
                -Name $name `
                -ValueName $name `
                -Command $display `
                -ValueKind ([string]$kind) `
                -RawValue $rawValue `
                -Enabled $true))
        }
    }

    return @($items)
}
