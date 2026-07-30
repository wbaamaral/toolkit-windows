function Get-ToolkitConfiguration {
    <#
    .SYNOPSIS
        Le a configuracao persistente do WBA Windows Toolkit.

    .DESCRIPTION
        Carrega o arquivo config.json em ProgramData. Quando o arquivo nao existe, retorna uma configuracao vazia
        com o caminho esperado para uso por outras funcoes.

    .PARAMETER ConfigPath
        Caminho alternativo para o arquivo config.json. Quando omitido, usa o caminho padrão em ProgramData.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $basePath = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
        $ConfigPath = Join-Path $basePath 'WBA\WindowsToolkit\config.json'
    }

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        }
        catch {
            throw "Nao foi possivel ler a configuracao do toolkit em $ConfigPath. $($_.Exception.Message)"
        }
    }
    else {
        $config = [pscustomobject]@{}
    }

    if ($null -eq $config.PSObject.Properties['ConfigPath']) {
        $config | Add-Member -MemberType NoteProperty -Name ConfigPath -Value $ConfigPath
    }

    return $config
}
