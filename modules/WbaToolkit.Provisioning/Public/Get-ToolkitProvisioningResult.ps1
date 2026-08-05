function Get-ToolkitProvisioningResult {
    <#
    .SYNOPSIS
        Le o relatorio final sanitizado de um deployment concluido.

    .DESCRIPTION
        Le Results\<deploymentId>\result.json, gerado por Complete-ToolkitProvisioning ao
        final da execucao. O conteudo ja passou por sanitizacao de segredos.

    .PARAMETER DeploymentId
        Identificador do deployment.

    .EXAMPLE
        Get-ToolkitProvisioningResult -DeploymentId 'filial-pvh-estacao-018'

    .OUTPUTS
        System.Management.Automation.PSCustomObject — o relatorio, ou $null se ainda nao existir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentId
    )

    $paths = Get-ToolkitProvisioningPaths
    $reportPath = Join-Path (Join-Path $paths.Results $DeploymentId) 'result.json'

    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        Write-Warning "Nenhum relatorio encontrado para o deployment '$DeploymentId' (execucao ainda nao concluida?)."
        return $null
    }

    Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
}
