function Test-ToolkitActivationDesiredState {
    <#
    .SYNOPSIS
        Etapa activation.apply — verifica se a chave de produto declarada ja esta instalada.

    .DESCRIPTION
        Identidade da chave e o 'partialProductKey' (os 5 caracteres finais, o mesmo
        segmento que o Windows expoe abertamente em qualquer diagnostico) — nunca a chave
        completa. A chave completa so e resolvida via secretRef dentro de Set, e somente
        no momento de aplicar; Test nunca decifra o segredo.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status, Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $config = $Context.Config
    if (-not (Test-ToolkitPropertyPresent -InputObject $config -Name 'activation')) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'activation' nao declarada."; Evidence = $null }
    }

    $desiredPartial = [string]$config.activation.partialProductKey

    $product = @(Get-CimInstanceSafe -ClassName 'SoftwareLicensingProduct' -Namespace 'root/cimv2' -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' and PartialProductKey<>null") |
        Select-Object -First 1

    $currentPartial = if ($product) { [string]$product.PartialProductKey } else { $null }
    $isCompliant = ($currentPartial -and $currentPartial.ToUpperInvariant() -eq $desiredPartial.ToUpperInvariant())

    $evidence = [pscustomobject]@{ DesiredPartialProductKey = $desiredPartial; CurrentPartialProductKey = $currentPartial }

    if ($isCompliant) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'Chave de produto declarada ja instalada.'; Evidence = $evidence }
    }

    return [pscustomobject]@{ Status = 'Changed'; Message = 'Chave de produto declarada ainda nao instalada.'; Evidence = $evidence }
}
