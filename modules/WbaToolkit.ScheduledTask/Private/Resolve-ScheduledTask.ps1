function Resolve-ScheduledTask {
    <#
    .SYNOPSIS
        Localiza uma unica tarefa agendada pelo nome, sem adivinhar.

    .DESCRIPTION
        Procura primeiro pelo nome exato (curingas no nome sao tratados como texto).
        Sem correspondencia exata, aceita correspondencia parcial no nome ou no caminho
        somente quando ela e unica. Mais de um candidato gera erro listando-os: os
        chamadores incluem Unregister/Disable/Start, e escolher "o primeiro" podia
        remover a tarefa errada em execucao -Silent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath
    )

    $getParams = @{ TaskName = [System.Management.Automation.WildcardPattern]::Escape($TaskName) }
    if ($TaskPath) { $getParams['TaskPath'] = $TaskPath }

    $exact = @(Get-ScheduledTask @getParams -ErrorAction SilentlyContinue)
    if ($exact.Count -eq 1) { return $exact[0] }
    if ($exact.Count -gt 1) {
        $nomes = ($exact | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" }) -join ', '
        throw "Nome de tarefa '$TaskName' ambiguo; informe -TaskPath. Candidatas: $nomes"
    }

    $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    $partial = @($allTasks | Where-Object {
        $_.TaskName.IndexOf($TaskName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $_.TaskPath.IndexOf($TaskName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    })

    if ($partial.Count -gt 1) {
        $nomes = ($partial | Select-Object -First 10 | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" }) -join ', '
        throw "Nenhuma tarefa com o nome exato '$TaskName' e $($partial.Count) correspondencias parciais; informe o nome exato. Candidatas: $nomes"
    }

    $partial | Select-Object -First 1
}
