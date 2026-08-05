function Uninstall-ToolkitProvisioning {
    <#
    .SYNOPSIS
        Remove a tarefa agendada de provisionamento.

    .DESCRIPTION
        Remove somente a tarefa agendada por padrao. O estado, os relatorios e a
        configuracao em %ProgramData%\WBA\Provisioning sao evidencia operacional e so sao
        removidos com -RemoveState explicito (alto impacto, exige confirmacao).

    .PARAMETER RemoveState
        Remove tambem toda a arvore %ProgramData%\WBA\Provisioning, incluindo estado,
        relatorios e configuracoes copiadas. Destrutivo e irreversivel.

    .EXAMPLE
        Uninstall-ToolkitProvisioning

    .EXAMPLE
        Uninstall-ToolkitProvisioning -RemoveState -Confirm:$false

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [switch]$RemoveState
    )

    $taskResult = Unregister-ToolkitProvisioningTask

    if (-not $RemoveState) {
        return [pscustomobject]@{ Success = $taskResult.Success; Message = $taskResult.Message }
    }

    $paths = Get-ToolkitProvisioningPaths
    if (Test-Path -LiteralPath $paths.Root) {
        if ($PSCmdlet.ShouldProcess($paths.Root, 'Remover toda a arvore de estado de provisionamento (irreversivel)')) {
            Remove-Item -LiteralPath $paths.Root -Recurse -Force
        }
    }

    [pscustomobject]@{
        Success = $taskResult.Success
        Message = "$($taskResult.Message) Estado removido de $($paths.Root)."
    }
}
