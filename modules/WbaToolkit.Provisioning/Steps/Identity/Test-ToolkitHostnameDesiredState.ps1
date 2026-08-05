function Test-ToolkitHostnameDesiredState {
    <#
    .SYNOPSIS
        Etapa identity.hostname — verifica se o nome do computador atende a configuracao.

    .DESCRIPTION
        Usada tanto como TestFunction quanto como VerifyFunction do manifesto da etapa
        (ciclo Test -> Set -> Verify). Sem efeitos colaterais.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State (ver Invoke-ToolkitProvisioningEngine).

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status (Skipped|Compliant|Changed|Failed), Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $config = $Context.Config
    $desiredName = $null
    if ($config -and $config.PSObject.Properties.Name -contains 'computer' -and
        $config.computer.PSObject.Properties.Name -contains 'name') {
        $desiredName = [string]$config.computer.name
    }

    if ([string]::IsNullOrWhiteSpace($desiredName)) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'computer.name' nao declarada."; Evidence = $null }
    }

    $currentName = $env:COMPUTERNAME

    if ($currentName -eq $desiredName) {
        return [pscustomobject]@{
            Status   = 'Compliant'
            Message  = "Nome do computador ja e '$desiredName'."
            Evidence = [pscustomobject]@{ CurrentName = $currentName }
        }
    }

    return [pscustomobject]@{
        Status   = 'Changed'
        Message  = "Nome do computador diverge: atual '$currentName', desejado '$desiredName'."
        Evidence = [pscustomobject]@{ CurrentName = $currentName; DesiredName = $desiredName }
    }
}
