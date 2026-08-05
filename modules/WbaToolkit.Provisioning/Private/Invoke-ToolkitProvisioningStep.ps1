function Invoke-ToolkitProvisioningStep {
    <#
    .SYNOPSIS
        Executa uma etapa seguindo o ciclo Test -> Set -> Verify.

    .DESCRIPTION
        SPEC-PROVISIONING-ENGINE: se Test comprovar conformidade, retorna Compliant sem
        chamar Set. Depois de Set, Verify deve comprovar o resultado antes do checkpoint
        de sucesso. Toda mensagem de erro passa por Protect-ToolkitProvisioningLogValue
        antes de entrar no resultado — nenhuma excecao bruta chega ao estado ou ao log.

    .PARAMETER StepManifest
        Manifesto da etapa (Get-ToolkitProvisioningStepRegistry).

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State, repassado as funcoes Test/Set/Verify.

    .PARAMETER Attempt
        Numero da tentativa corrente (1-based).

    .OUTPUTS
        System.Management.Automation.PSCustomObject — ver New-ToolkitProvisioningStepResult.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$StepManifest,

        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [int]$Attempt = 1
    )

    $startedAt = Get-Date
    $testFn    = $StepManifest.TestFunction
    $setFn     = $StepManifest.SetFunction
    $verifyFn  = $StepManifest.VerifyFunction

    try {
        $testResult = & $testFn -Context $Context

        if ($testResult.Status -eq 'Skipped') {
            return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'Skipped' `
                -Attempt $Attempt -StartedAt $startedAt -Message $testResult.Message
        }

        if ($testResult.Status -eq 'Compliant') {
            return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'Compliant' `
                -Attempt $Attempt -StartedAt $startedAt -Message $testResult.Message -Evidence $testResult.Evidence
        }

        if ($testResult.Status -eq 'Failed') {
            $safeMessage = Protect-ToolkitProvisioningLogValue -InputObject $testResult.Message
            return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'Failed' `
                -Attempt $Attempt -StartedAt $startedAt -Message $safeMessage -ErrorCode 'PreconditionFailed'
        }

        # $testResult.Status -eq 'Changed' -> converge via Set, depois comprova via Verify.
        $setResult = & $setFn -Context $Context

        if ($WhatIfPreference) {
            # Set nao executou (ShouldProcess recusou sob -WhatIf); Verify recompovaria
            # o mesmo estado "Changed" e seria mal-interpretado como falha de Verify.
            # Reporta o plano sem chamar Verify.
            return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'Changed' `
                -Changed $true -Attempt $Attempt -StartedAt $startedAt `
                -Message "(WhatIf) $($testResult.Message)" -Evidence $testResult.Evidence
        }

        if ($setResult.RebootRequired) {
            return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'RebootRequired' `
                -Changed $true -RebootRequired $true -Attempt $Attempt -StartedAt $startedAt `
                -Message $setResult.Message -Evidence $setResult.Evidence
        }

        $verifyResult = & $verifyFn -Context $Context

        if ($verifyResult.Status -ne 'Compliant') {
            $safeMessage = Protect-ToolkitProvisioningLogValue -InputObject "Verificacao pos-Set falhou: $($verifyResult.Message)"
            return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'Failed' `
                -Changed $true -Attempt $Attempt -StartedAt $startedAt -Message $safeMessage -ErrorCode 'VerifyFailed'
        }

        return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'Changed' `
            -Changed $true -Attempt $Attempt -StartedAt $startedAt -Message $setResult.Message -Evidence $verifyResult.Evidence
    }
    catch {
        $safeMessage = Protect-ToolkitProvisioningLogValue -InputObject $_.Exception.Message
        return New-ToolkitProvisioningStepResult -StepId $StepManifest.Id -Status 'Failed' `
            -Attempt $Attempt -StartedAt $startedAt -Message $safeMessage -ErrorCode 'UnhandledException'
    }
}
