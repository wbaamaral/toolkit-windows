function Enable-StartupItem {
    <#
    .SYNOPSIS
        Reativa um ou mais itens de inicializacao gerenciados pelo toolkit.

    .DESCRIPTION
        Restaura entradas de inicializacao previamente desabilitadas por Disable-StartupItem.
        Recupera os dados do registro WBA e desfaz a operacao original para cada tipo
        de fonte (Registry, StartupFolder, ScheduledTask).
        Aceita item unico ou lista de itens retornados por Get-StartupItem.

    .PARAMETER Item
        Um ou mais itens de inicializacao a reativar.
        Deve ser um item com ManagedDisabled = $true retornado por Get-StartupItem.

    .PARAMETER DryRun
        Simula a operacao sem efetuar alteracoes no sistema.

    .EXAMPLE
        $itens = Get-StartupItem | Where-Object { $_.ManagedDisabled -eq $true }
        Enable-StartupItem -Item $itens

        Reativa todos os itens que foram desabilitados pelo toolkit.

    .EXAMPLE
        Get-StartupItem | Where-Object { $_.Name -eq 'OneDrive' } | ForEach-Object {
            Enable-StartupItem -Item $_
        }

        Reativa o OneDrive na inicializacao.

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
        if ($currentItem.Enabled -and -not $currentItem.ManagedDisabled) {
            Write-Warn "Entrada '$($currentItem.Name)' ja esta habilitada."
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Enable'; Success = $false; Message = 'Ja habilitada.' }
            continue
        }

        if ($DryRun) {
            Write-Verbose "DRY-RUN: habilitaria inicializacao '$($currentItem.Name)'."
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Enable'; Success = $true; Message = 'DryRun.' }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($currentItem.Name, 'Habilitar inicializacao')) {
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Enable'; Success = $true; Message = 'WhatIf.' }
            continue
        }

        try {
            switch ($currentItem.SourceType) {
                'Registry' {
                    # Nao usar New-Item -Force em chave existente: isso recria a chave
                    # e apaga TODOS os demais valores (ex.: outras entradas Run).
                    if (-not (Test-Path -LiteralPath $currentItem.Location)) {
                        New-Item -Path $currentItem.Location -Force -ErrorAction Stop | Out-Null
                    }
                    # Restaura preservando o tipo nativo (RawValue + ValueKind).
                    $kind  = if ($currentItem.ValueKind) { [string]$currentItem.ValueKind } else { 'String' }
                    $value = if ($null -ne $currentItem.RawValue) { $currentItem.RawValue } else { $currentItem.Command }
                    New-ItemProperty -Path $currentItem.Location -Name $currentItem.ValueName -Value $value -PropertyType $kind -Force -ErrorAction Stop | Out-Null
                    Remove-StartupStoreItem -Id $currentItem.Id
                }
                'StartupFolder' {
                    if (-not $currentItem.BackupPath -or -not (Test-Path -LiteralPath $currentItem.BackupPath)) {
                        throw "Backup do atalho nao encontrado para '$($currentItem.Name)'."
                    }
                    New-Item -Path $currentItem.Location -ItemType Directory -Force | Out-Null
                    Move-Item -LiteralPath $currentItem.BackupPath -Destination (Join-Path $currentItem.Location $currentItem.ValueName) -Force
                    Remove-StartupStoreItem -Id $currentItem.Id
                }
                'ScheduledTask' {
                    Enable-ScheduledTask -TaskName $currentItem.ValueName -TaskPath $currentItem.Location -ErrorAction Stop | Out-Null
                    Remove-StartupStoreItem -Id $currentItem.Id
                }
                default {
                    throw "Tipo de inicializacao nao suportado: $($currentItem.SourceType)"
                }
            }

            Write-Ok "Inicializacao habilitada: $($currentItem.Name)"
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Enable'; Success = $true; Message = 'OK.' }
        }
        catch {
            Write-Verbose "Falha ao habilitar '$($currentItem.Name)': $($_.Exception.Message)"
            Write-Warn "Falha ao habilitar '$($currentItem.Name)': $($_.Exception.Message)"
            [pscustomobject]@{ Name = $currentItem.Name; Action = 'Enable'; Success = $false; Message = $_.Exception.Message }
        }
    }

    return @($results)
}
