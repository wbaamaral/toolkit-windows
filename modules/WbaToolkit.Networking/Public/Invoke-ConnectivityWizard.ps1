function Invoke-ConnectivityWizard {
    <#
    .SYNOPSIS
        Executa um wizard simples para o diagnóstico de conectividade.

    .DESCRIPTION
        Apresenta um menu mínimo no console permitindo ao operador iniciar a bateria completa de testes
        de conectividade via Invoke-ConnectivityTest e exibir o resultado com Show-ConnectivityReport.
        Para wizard interativo por alvo específico, use Invoke-TargetConnectivityWizard.

    .EXAMPLE
        Invoke-ConnectivityWizard
    #>
    [CmdletBinding()]
    param()

    Write-Host 'WBA Connectivity Tester' -ForegroundColor Cyan
    Write-Host '1. Executar teste completo'
    Write-Host '2. Cancelar'

    $choice = Read-Host 'Escolha uma opcao'
    switch ($choice) {
        '1' {
            $report = Invoke-ConnectivityTest
            Show-ConnectivityReport -Report $report
            $report
        }
        default {
        Write-Warn 'Operacao cancelada.'
            return
        }
    }
}
