function Remove-StartupItem {
    <#
    .SYNOPSIS
        Remove definitivamente um ou mais itens de inicializacao do Windows.

    .DESCRIPTION
        Remove entradas de inicializacao de forma permanente e irreversivel.
        Exige confirmacao textual antes de prosseguir. Suporta Registry,
        StartupFolder e ScheduledTask. Itens gerenciados (ManagedDisabled) tem
        seus backups e registros WBA limpos junto com a remocao.
        Aceita item unico ou lista.

    .PARAMETER Item
        Um ou mais itens de inicializacao a remover permanentemente.

    .PARAMETER DryRun
        Simula a operacao sem efetuar alteracoes no sistema.

    .EXAMPLE
        $item = Get-StartupItem | Where-Object { $_.Name -eq 'Updater' }
        Remove-StartupItem -Item $item

        Remove o item 'Updater' da inicializacao apos confirmacao textual.

    .EXAMPLE
        $desabilitados = Get-StartupItem | Where-Object { $_.ManagedDisabled }
        Remove-StartupItem -Item $desabilitados

        Remove todos os itens gerenciados desabilitados apos confirmacao.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array de objetos com as propriedades: Name, Action, Success, Message.
        Retorna array vazio quando o operador cancela a confirmacao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Item,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $targets = @($Item)
    $count = $targets.Count
    $plural = if ($count -gt 1) { "$count entradas" } else { 'esta entrada' }

    $confirmation = Read-Host "Para remover definitivamente $plural da inicializacao, digite REMOVER INICIALIZACAO"
    if ($confirmation -ne 'REMOVER INICIALIZACAO') {
        Write-Warn 'Remocao cancelada.'
        return @()
    }

    $results = foreach ($currentItem in $targets) {
        if ($DryRun) {
            Write-Verbose "DRY-RUN: removeria inicializacao '$($currentItem.Name)'."
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Remove'; Success = $true; Message = 'DryRun.' }
            continue
        }

        try {
            switch ($currentItem.SourceType) {
                'Registry' {
                    if ($currentItem.ManagedDisabled) {
                        Remove-StartupStoreItem -Id $currentItem.Id
                    }
                    elseif (Test-Path -LiteralPath $currentItem.Location) {
                        Remove-ItemProperty -LiteralPath $currentItem.Location -Name $currentItem.ValueName -ErrorAction Stop
                    }
                }
                'StartupFolder' {
                    if ($currentItem.ManagedDisabled -and $currentItem.BackupPath -and (Test-Path -LiteralPath $currentItem.BackupPath)) {
                        Remove-Item -LiteralPath $currentItem.BackupPath -Force
                        Remove-StartupStoreItem -Id $currentItem.Id
                    }
                    elseif ($currentItem.Command -and (Test-Path -LiteralPath $currentItem.Command)) {
                        Remove-Item -LiteralPath $currentItem.Command -Force
                    }
                }
                'ScheduledTask' {
                    Unregister-ScheduledTask -TaskName $currentItem.ValueName -TaskPath $currentItem.Location -Confirm:$false -ErrorAction Stop
                    if ($currentItem.ManagedDisabled) {
                        Remove-StartupStoreItem -Id $currentItem.Id
                    }
                }
                default {
                    throw "Tipo de inicializacao nao suportado: $($currentItem.SourceType)"
                }
            }

            Write-Ok "Entrada removida da inicializacao: $($currentItem.Name)"
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Remove'; Success = $true; Message = 'OK.' }
        }
        catch {
            Write-Verbose "Falha ao remover '$($currentItem.Name)': $($_.Exception.Message)"
            Write-Warn "Falha ao remover '$($currentItem.Name)': $($_.Exception.Message)"
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Remove'; Success = $false; Message = $_.Exception.Message }
        }
    }

    return @($results)
}
