function Get-ScheduledTaskDetail {
    <#
    .SYNOPSIS
        Retorna detalhes completos de uma tarefa agendada.
    .DESCRIPTION
        Inclui acoes, triggers, principal, configuracao e historico de execucao.
    .PARAMETER TaskName
        Nome da tarefa.
    .PARAMETER TaskPath
        Caminho da pasta (opcional).
    .OUTPUTS
        PSCustomObject com detalhes completos da tarefa.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath
    )

    $task = Resolve-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    if (-not $task) { throw "Tarefa '$TaskName' nao encontrada." }

    ConvertTo-ScheduledTaskInfo -Task $task
}
