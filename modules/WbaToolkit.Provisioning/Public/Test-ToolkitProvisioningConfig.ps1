function Test-ToolkitProvisioningConfig {
    <#
    .SYNOPSIS
        Valida um arquivo de configuracao de provisionamento sem alterar o sistema.

    .DESCRIPTION
        Le o JSON, confirma que e sintaticamente valido e aplica as regras semanticas de
        SPEC-PROVISIONING-CONFIG (schemaVersion e deploymentId obrigatorios, campos
        desconhecidos rejeitados, segredo em texto claro rejeitado). Nunca cria tarefa
        agendada, nunca copia o arquivo e nunca altera o sistema.

    .PARAMETER Path
        Caminho do arquivo JSON de configuracao.

    .PARAMETER ResolveTargets
        Reservado para fases futuras (rede, storage, certificados): quando implementado,
        permitira consultar hardware/adaptadores sem alterar o sistema. Sem efeito na
        Fase 1 alem de um aviso informativo.

    .EXAMPLE
        Test-ToolkitProvisioningConfig -Path .\provisioning.json

    .OUTPUTS
        System.Management.Automation.PSCustomObject — IsValid, Errors, Warnings, Sha256.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$ResolveTargets
    )

    $imported = Import-ToolkitProvisioningConfig -Path $Path
    $result   = Test-ToolkitProvisioningSchema -Config $imported.Config

    $warnings = @($result.Warnings)
    if ($ResolveTargets) {
        $warnings += 'ResolveTargets ainda nao resolve alvos de rede/storage/certificados na Fase 1.'
    }

    [pscustomobject]@{
        IsValid  = $result.IsValid
        Errors   = $result.Errors
        Warnings = @($warnings)
        Sha256   = $imported.Sha256
        Path     = $imported.Path
    }
}
