function Unregister-ScheduledTaskByName {
    <#
    .SYNOPSIS
        Remove uma tarefa agendada por nome.
    .PARAMETER TaskName
        Nome da tarefa (ou busca parcial).
    .PARAMETER TaskPath
        Caminho da pasta (opcional).
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$TaskName,

        [Parameter(Mandatory = $false)]
        [string]$TaskPath
    )

    $task = Resolve-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    if (-not $task) { throw "Tarefa '$TaskName' nao encontrada." }

    if ($PSCmdlet.ShouldProcess($task.TaskName, 'Remover tarefa agendada')) {
        $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
        Write-Output "Tarefa '$($task.TaskName)' removida."
    }
}
