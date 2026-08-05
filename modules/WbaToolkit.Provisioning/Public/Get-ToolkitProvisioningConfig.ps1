function Get-ToolkitProvisioningConfig {
    <#
    .SYNOPSIS
        Le a copia de trabalho da configuracao de um deployment ja iniciado.

    .DESCRIPTION
        Le exclusivamente a copia protegida em Work\<deploymentId>\provisioning.json —
        nunca a origem original (Inbox/midia), que pode ter sido removida ou alterada
        apos a copia. Falha se o deployment nunca foi iniciado.

    .PARAMETER DeploymentId
        Identificador do deployment.

    .EXAMPLE
        Get-ToolkitProvisioningConfig -DeploymentId 'filial-pvh-estacao-018'

    .OUTPUTS
        System.Management.Automation.PSCustomObject — a configuracao convertida de JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentId
    )

    $paths = Get-ToolkitProvisioningPaths
    $configPath = Join-Path (Join-Path $paths.Work $DeploymentId) 'provisioning.json'

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Nenhuma copia de configuracao encontrada para o deployment '$DeploymentId' em '$configPath'."
    }

    (Import-ToolkitProvisioningConfig -Path $configPath).Config
}
