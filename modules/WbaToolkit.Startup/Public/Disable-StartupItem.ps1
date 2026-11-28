function Disable-StartupItem {
    <#
    .SYNOPSIS
        Desabilita um ou mais itens de inicializacao do Windows.

    .DESCRIPTION
        Desabilita entradas de inicializacao preservando os dados originais no registro
        WBA para permitir reativacao. Suporta Registry (chaves Run), StartupFolder
        (atalhos movidos) e ScheduledTask (tarefas desabilitadas).
        Aceita item unico ou lista de itens retornados por Get-StartupItem.

    .PARAMETER Item
        Um ou mais itens de inicializacao a desabilitar.
        Aceita o resultado direto de Get-StartupItem.

    .PARAMETER DryRun
        Simula a operacao sem efetuar alteracoes no sistema.

    .EXAMPLE
        $items = Get-StartupItem
        Disable-StartupItem -Item $items[0]

        Desabilita o primeiro item encontrado.

    .EXAMPLE
        Get-StartupItem | Where-Object { $_.Name -eq 'OneDrive' } | ForEach-Object {
            Disable-StartupItem -Item $_
        }

        Desabilita o OneDrive da inicializacao.

    .EXAMPLE
        $selecionados = Get-StartupItem | Where-Object { $_.SourceType -eq 'StartupFolder' }
        Disable-StartupItem -Item $selecionados -DryRun

        Simula a desativacao de todos os atalhos da pasta Startup.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array de objetos com as propriedades: Name, Action, Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Item,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $results = foreach ($currentItem in @($Item)) {
        if (-not $currentItem.Enabled) {
            Write-Warn "Entrada '$($currentItem.Name)' ja esta desabilitada."
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Disable'; Success = $false; Message = 'Ja desabilitada.' }
            continue
        }

        if ($DryRun) {
            Write-Verbose "DRY-RUN: desabilitaria inicializacao '$($currentItem.Name)'."
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Disable'; Success = $true; Message = 'DryRun.' }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($currentItem.Name, 'Desabilitar inicializacao')) {
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Disable'; Success = $true; Message = 'WhatIf.' }
            continue
        }

        # Se a desativacao falhar depois de gravar o store, o registro e desfeito: senao Get-StartupItem
        # mostraria a entrada como desligada (o item do store prevalece) com ela ainda ativa.
        $storeSaved = $false
        try {
            switch ($currentItem.SourceType) {
                'Registry' {
                    Save-StartupStoreItem -Item $currentItem
                    $storeSaved = $true
                    Remove-ItemProperty -LiteralPath $currentItem.Location -Name $currentItem.ValueName -ErrorAction Stop
                }
                'StartupFolder' {
                    $disabledRoot = Get-StartupDisabledRoot
                    New-Item -Path $disabledRoot -ItemType Directory -Force | Out-Null
                    $backupPath = Join-Path $disabledRoot ("$($currentItem.Id)-$($currentItem.ValueName)")
                    Save-StartupStoreItem -Item $currentItem -BackupPath $backupPath
                    $storeSaved = $true
                    Move-Item -LiteralPath $currentItem.Command -Destination $backupPath -Force
                }
                'ScheduledTask' {
                    Save-StartupStoreItem -Item $currentItem
                    $storeSaved = $true
                    Disable-ScheduledTask -TaskName $currentItem.ValueName -TaskPath $currentItem.Location -ErrorAction Stop | Out-Null
                }
                default {
                    throw "Tipo de inicializacao nao suportado: $($currentItem.SourceType)"
                }
            }

            Write-Ok "Inicializacao desabilitada: $($currentItem.Name)"
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Disable'; Success = $true; Message = 'OK.' }
        }
        catch {
            $failure = $_.Exception.Message
            if ($storeSaved) {
                try { Remove-StartupStoreItem -Id $currentItem.Id -Confirm:$false }
                catch { Write-Verbose "Nao foi possivel desfazer o store de '$($currentItem.Name)': $($_.Exception.Message)" }
            }
            Write-Verbose "Falha ao desabilitar '$($currentItem.Name)': $failure"
            Write-Warn "Falha ao desabilitar '$($currentItem.Name)': $failure"
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Disable'; Success = $false; Message = $failure }
        }
    }

    return @($results)
}
