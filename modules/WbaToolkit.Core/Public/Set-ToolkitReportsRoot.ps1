function Set-ToolkitReportsRoot {
    <#
    .SYNOPSIS
        Salva o diretorio preferido para relatorios do WBA Windows Toolkit.

    .DESCRIPTION
        Grava a chave ReportsRoot no arquivo de configuracao persistente do toolkit. Scripts e funcoes que nao
        receberem um caminho explicitamente devem consultar esta configuracao antes de usar o padrao global.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $basePath = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
        $ConfigPath = Join-Path $basePath 'WBA\WindowsToolkit\config.json'
    }

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $configDir = Split-Path -Parent $ConfigPath
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null

    $config = Get-ToolkitConfiguration -ConfigPath $ConfigPath
    $data = [ordered]@{}
    foreach ($property in $config.PSObject.Properties) {
        if ($property.Name -ne 'ConfigPath') {
            $data[$property.Name] = $property.Value
        }
    }

    $data['ReportsRoot'] = $resolvedPath
    $encoding = [System.Text.UTF8Encoding]::new($true)
    try {
        Write-TextFileUtf8 -Path $ConfigPath -Content ($data | ConvertTo-Json -Depth 6)
    }
    catch {
        throw "Nao foi possivel gravar a configuracao em '$ConfigPath'. $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Success = $true
        ReportsRoot = $resolvedPath
        ConfigPath = $ConfigPath
    }
}
