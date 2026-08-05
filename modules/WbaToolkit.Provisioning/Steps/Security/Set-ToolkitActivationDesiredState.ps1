function Set-ToolkitActivationDesiredState {
    <#
    .SYNOPSIS
        Etapa activation.apply — instala a chave de produto declarada via slmgr.vbs /ipk.

    .DESCRIPTION
        Resolve a chave completa por secretRef e a mantem em memoria apenas pelo tempo da
        chamada a slmgr.vbs; nunca a registra em log, estado ou excecao. MVP nao executa
        ativacao online (/ato) nem KMS — apenas instala a chave, conforme
        SPEC-PROVISIONING-CONFIG ('activation: chave somente por secretRef').

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

    if (-not $PSCmdlet.ShouldProcess('Chave de produto Windows', 'Instalar via slmgr.vbs /ipk')) {
        return [pscustomobject]@{ RebootRequired = $false; Message = 'Operacao cancelada (WhatIf).'; Evidence = $null }
    }

    $secureKey = Resolve-ToolkitProvisioningSecret -SecretRef ([string]$activationConfig.productKeySecretRef) -Paths $Context.Paths
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

        $slmgrPath = Join-Path $env:windir 'System32\slmgr.vbs'
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'cscript.exe'
        $startInfo.Arguments = "//nologo `"$slmgrPath`" /ipk $plainKey"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $process.Start() | Out-Null
        $process.WaitForExit(60000) | Out-Null
        $exitCode = $process.ExitCode
    }
    finally {
        $plainKey = $null
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $secureKey = $null
    }

    if ($exitCode -ne 0) {
        throw "slmgr.vbs /ipk terminou com codigo $exitCode."
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = 'Chave de produto instalada via slmgr.vbs /ipk.'
        Evidence       = [pscustomobject]@{ ExitCode = $exitCode }
    }
}
