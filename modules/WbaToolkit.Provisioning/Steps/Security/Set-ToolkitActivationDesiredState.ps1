function Set-ToolkitActivationDesiredState {
    <#
    .SYNOPSIS
        Etapa activation.apply — instala a chave de produto declarada via
        SoftwareLicensingService::InstallProductKey.

    .DESCRIPTION
        Resolve a chave completa por secretRef e a mantem em memoria apenas pelo tempo da
        chamada ao metodo CIM; nunca a registra em log, estado ou excecao. Usa
        Invoke-CimMethod em vez de slmgr.vbs via processo externo porque um processo
        externo expoe a chave completa em texto claro na linha de comando (visivel via
        Win32_Process/auditoria de criacao de processo enquanto o processo roda); a
        chamada CIM nao tem essa exposicao. MVP nao executa ativacao online (/ato) nem
        KMS — apenas instala a chave, conforme SPEC-PROVISIONING-CONFIG
        ('activation: chave somente por secretRef').

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $activationConfig = $Context.Config.activation
    if (-not (Test-ToolkitPropertyPresent -InputObject $activationConfig -Name 'productKeySecretRef')) {
        throw "'activation.productKeySecretRef' ausente; instalacao de chave recusada."
    }

    if (-not $PSCmdlet.ShouldProcess('Chave de produto Windows', 'Instalar via SoftwareLicensingService::InstallProductKey')) {
        return [pscustomobject]@{ RebootRequired = $false; Message = 'Operacao cancelada (WhatIf).'; Evidence = $null }
    }

    $secureKey = Resolve-ToolkitProvisioningSecret -SecretRef ([string]$activationConfig.productKeySecretRef) -Paths $Context.Paths
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $result = Invoke-CimMethod -ClassName 'SoftwareLicensingService' -Namespace 'root/cimv2' -MethodName 'InstallProductKey' -Arguments @{ ProductKey = $plainKey }
        $returnValue = [int]$result.ReturnValue
    }
    finally {
        $plainKey = $null
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $secureKey = $null
    }

    if ($returnValue -ne 0) {
        throw "SoftwareLicensingService::InstallProductKey retornou codigo $returnValue."
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = 'Chave de produto instalada via SoftwareLicensingService::InstallProductKey.'
        Evidence       = [pscustomobject]@{ ReturnValue = $returnValue }
    }
}
