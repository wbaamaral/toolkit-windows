function Get-ToolkitReportsRoot {
    <#
    .SYNOPSIS
        Resolve a raiz global de relatorios do toolkit.

    .DESCRIPTION
        Aplica a precedencia padronizada: caminho informado pelo usuario, configuracao persistente ReportsRoot e,
        por fim, C:\WBA\Relatorios.

    .PARAMETER Path
        Caminho informado explicitamente pelo usuário. Quando presente, tem prioridade máxima.

    .PARAMETER ConfigPath
        Caminho alternativo para o arquivo config.json. Quando omitido, usa o caminho padrão em ProgramData.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    $config = Get-ToolkitConfiguration -ConfigPath $ConfigPath
    if ($null -ne $config.PSObject.Properties['ReportsRoot'] -and -not [string]::IsNullOrWhiteSpace($config.ReportsRoot)) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([string]$config.ReportsRoot)
    }

    return 'C:\WBA\Relatorios'
}
