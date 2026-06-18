function Invoke-StartupManager {
    <#
    .SYNOPSIS
        Gerenciador interativo de itens de inicializacao do Windows.

    .DESCRIPTION
        Apresenta um loop interativo para o operador selecionar e modificar entradas
        de inicializacao. Suporta desabilitar, reativar e remover itens das fontes
        Registry, StartupFolder e ScheduledTask.

        Retorna um array com o registro de todas as operacoes realizadas durante a sessao,
        permitindo que o chamador integre o historico ao seu proprio sistema de rastreamento.

    .PARAMETER DryRun
        Simula todas as operacoes sem efetuar alteracoes no sistema.

    .EXAMPLE
        Invoke-StartupManager

        Inicia o gerenciador interativo em modo real.

    .EXAMPLE
        Invoke-StartupManager -DryRun

        Inicia o gerenciador em modo de simulacao.

    .EXAMPLE
        $historico = Invoke-StartupManager
        $historico | Where-Object { $_.Success } | Format-Table Name, Action, Message

        Exibe apenas as operacoes bem-sucedidas da sessao.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array de objetos com as propriedades: Name, Action, Success, Message.
        Retorna array vazio quando nenhuma operacao e realizada.

    .NOTES
        Requer acesso administrativo para modificar itens de nivel Machine e tarefas agendadas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $sessionLog = [System.Collections.ArrayList]::new()

    while ($true) {
        $currentItems = @(Get-StartupItem)
        if (@($currentItems).Count -eq 0) {
            Write-Info 'Nenhuma entrada de inicializacao foi encontrada.'
            break
        }

        Show-StartupItem -Items $currentItems
        $choice = Read-Host 'Digite o numero da entrada para alterar ou 0 para sair'
        if ($choice -in @('', '0')) {
            break
        }

        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt @($currentItems).Count) {
            Write-Warn 'Opcao invalida.'
            continue
        }

        $item = $currentItems[$number - 1]
        Write-Host ''
        Write-Host "Selecionado: $($item.Name)" -ForegroundColor Cyan
        Write-Host "Comando: $($item.Command)"
        Write-Host '[D] Desabilitar para diagnostico'
        Write-Host '[H] Habilitar novamente'
        Write-Host '[R] Remover definitivamente da inicializacao'
        Write-Host '[V] Voltar'
        $action = (Read-Host 'Acao').Trim().ToUpperInvariant()

        $results = switch ($action) {
            'D' { Disable-StartupItem -Item $item -DryRun:$DryRun }
            'H' { Enable-StartupItem -Item $item -DryRun:$DryRun }
            'R' { Remove-StartupItem -Item $item -DryRun:$DryRun }
            default { @() }
        }

        foreach ($r in @($results)) {
            $null = $sessionLog.Add($r)
        }
    }

    return @($sessionLog)
}
