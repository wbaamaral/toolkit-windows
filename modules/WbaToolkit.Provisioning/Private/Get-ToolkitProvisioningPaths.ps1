function Get-ToolkitProvisioningPaths {
    <#
    .SYNOPSIS
        Resolve as pastas de execucao do provisionamento sob ProgramData.

    .DESCRIPTION
        Centraliza os caminhos definidos em SPEC-PROVISIONING-ENGINE (Inbox, Work, Logs,
        Results, Secrets, Quarantine). Aceita -Root para testes (aponta para um diretorio
        temporario em vez de %ProgramData%\WBA\Provisioning).

    .PARAMETER Root
        Raiz alternativa. Uso exclusivo de testes automatizados.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Join-Path $env:ProgramData 'WBA\Provisioning'
    }

    [pscustomobject]@{
        Root       = $Root
        Inbox      = Join-Path $Root 'Inbox'
        Work       = Join-Path $Root 'Work'
        Logs       = Join-Path $Root 'Logs'
        Results    = Join-Path $Root 'Results'
        Secrets    = Join-Path $Root 'Secrets'
        Quarantine = Join-Path $Root 'Quarantine'
    }
}
