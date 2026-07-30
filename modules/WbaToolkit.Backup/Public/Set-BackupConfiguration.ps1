function Set-BackupConfiguration {
    <#
    .SYNOPSIS
        Atualiza a configuracao de backup.
    .DESCRIPTION
        Modifica o arquivo config-backup.json.
    .PARAMETER Settings
        Hashtable com as configuracoes a atualizar.
    .PARAMETER Reset
        Restaura a configuracao padrao.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [hashtable]$Settings,

        [switch]$Reset
    )

    $configPath = Get-BackupConfigurationInternal
    $configDir = Join-Path $env:ProgramData 'WBA\WindowsToolkit'

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $targetPath = if ($configPath) { $configPath } else { Join-Path $configDir 'config-backup.json' }

    if ($Reset) {
        $default = Get-BackupConfiguration
        if ($PSCmdlet.ShouldProcess($targetPath, 'Restaurar configuracao padrao')) {
            $default | ConvertTo-Json -Depth 8 | Set-Content -Path $targetPath -Encoding UTF8
            Write-Output "Configuracao restaurada para padrao."
        }
        return
    }

    if (-not $Settings) { throw "Nenhuma configuracao fornecida." }

    $current = Get-BackupConfiguration
    $currentJson = $current | ConvertTo-Json -Depth 8

    foreach ($key in $Settings.Keys) {
        if ($current.PSObject.Properties[$key]) {
            foreach ($subKey in $Settings[$key].Keys) {
                if ($current.$key.PSObject.Properties[$subKey]) {
                    $current.$key.$subKey = $Settings[$key][$subKey]
                }
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($targetPath, 'Atualizar configuracao')) {
        $current | ConvertTo-Json -Depth 8 | Set-Content -Path $targetPath -Encoding UTF8
        Write-Output "Configuracao atualizada."
    }
}
