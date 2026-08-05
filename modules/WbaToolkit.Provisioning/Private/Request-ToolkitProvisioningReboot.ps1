function Request-ToolkitProvisioningReboot {
    <#
    .SYNOPSIS
        Aplica a politica de reboot apos uma etapa sinalizar RebootRequired.

    .DESCRIPTION
        SPEC-PROVISIONING-ENGINE: reboot nao e sinalizado por texto em stdout — a etapa
        retorna RebootRequired e o executor ja persistiu o checkpoint antes de chamar
        esta funcao. 'Never' transforma a solicitacao em pendencia no relatorio;
        'WhenRequired' reinicia; 'Manual' encerra com codigo especifico e aguarda o
        operador.

    .PARAMETER RebootPolicy
        Never | WhenRequired | Manual.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Action ('None'|'Rebooting'|'AwaitingManualReboot'), Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Never', 'WhenRequired', 'Manual')]
        [string]$RebootPolicy
    )

    switch ($RebootPolicy) {
        'Never' {
            return [pscustomobject]@{
                Action  = 'None'
                Message = "Reboot necessario, mas politica 'Never' mantem a execucao pendente ate acao manual."
            }
        }
        'Manual' {
            return [pscustomobject]@{
                Action  = 'AwaitingManualReboot'
                Message = "Reboot necessario. Politica 'Manual': aguardando reinicializacao pelo operador."
            }
        }
        'WhenRequired' {
            if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Reiniciar para continuar o provisionamento')) {
                Restart-Computer -Force
            }
            return [pscustomobject]@{
                Action  = 'Rebooting'
                Message = 'Reinicializacao solicitada pela politica WhenRequired.'
            }
        }
    }
}
