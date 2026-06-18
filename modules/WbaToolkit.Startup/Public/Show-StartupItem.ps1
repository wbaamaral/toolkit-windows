function Show-StartupItem {
    <#
    .SYNOPSIS
        Exibe a lista de itens de inicializacao no console.

    .DESCRIPTION
        Apresenta os itens de inicializacao formatados em tabela numerada com
        indicacao visual do estado (ON/OFF), tipo de fonte e escopo.

    .PARAMETER Items
        Array de itens de inicializacao retornado por Get-StartupItem.
        Aceita lista ou item unico.

    .EXAMPLE
        $items = Get-StartupItem
        Show-StartupItem -Items $items

        Exibe todos os itens de inicializacao encontrados.

    .EXAMPLE
        Get-StartupItem | Where-Object { $_.SourceType -eq 'Registry' } | ForEach-Object { $_ } | `
            & { param($i) Show-StartupItem -Items $i }

        Exibe apenas itens do Registro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items
    )

    Write-Host ''
    Write-Host 'Programas na inicializacao' -ForegroundColor Cyan
    Write-Host '-------------------------' -ForegroundColor Cyan

    $index = 1
    foreach ($item in @($Items)) {
        $stateText = if ($item.Enabled) { 'ON ' } else { 'OFF' }
        $color = if ($item.Enabled) { 'Green' } else { 'DarkGray' }
        Write-Host ("[{0,2}] " -f $index) -NoNewline
        Write-Host $stateText -ForegroundColor $color -NoNewline
        Write-Host (" {0} | {1} | {2}" -f $item.SourceType, $item.Scope, $item.Name)
        $index++
    }

    Write-Host ''
}
