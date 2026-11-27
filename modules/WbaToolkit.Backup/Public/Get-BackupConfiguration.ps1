function Get-BackupConfiguration {
    <#
    .SYNOPSIS
        Retorna a configuracao atual de backup.
    .DESCRIPTION
        Le o arquivo config-backup.json e retorna como objeto.
    .OUTPUTS
        PSCustomObject com configuracao de backup.
    #>
    [CmdletBinding()]
    param()

    $configPath = Get-BackupConfigurationInternal

    if (-not $configPath -or -not (Test-Path $configPath)) {
        Write-Warning "Arquivo config-backup.json nao encontrado. Usando valores padrao."
        return Get-BackupDefaultConfiguration
    }

    Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
