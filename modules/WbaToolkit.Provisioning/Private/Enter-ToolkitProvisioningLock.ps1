function Enter-ToolkitProvisioningLock {
    <#
    .SYNOPSIS
        Adquire o mutex global que impede duas execucoes simultaneas do motor.

    .DESCRIPTION
        SPEC-PROVISIONING-ENGINE exige mutex nomeado para concorrencia. Falha em adquirir
        dentro do timeout indica outra instancia em execucao — o chamador deve tratar
        como erro terminante, nunca ignorar silenciosamente.

    .PARAMETER TimeoutSeconds
        Tempo maximo de espera pelo mutex. Padrao: 5 segundos (o motor nao deve empilhar
        chamadas concorrentes por muito tempo).

    .OUTPUTS
        System.Threading.Mutex — passe para Exit-ToolkitProvisioningLock ao terminar.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 5
    )

    $mutex = New-Object System.Threading.Mutex($false, 'Global\WbaToolkitProvisioning')
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    }
    catch [System.Threading.AbandonedMutexException] {
        # Mutex abandonado por processo anterior finalizado sem liberar — estado do
        # disco ainda e a fonte da verdade; tratamos como adquirido.
        $acquired = $true
    }

    if (-not $acquired) {
        $mutex.Dispose()
        throw 'Nao foi possivel adquirir o mutex de provisionamento: outra execucao esta em andamento.'
    }

    return $mutex
}
