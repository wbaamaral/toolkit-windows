function Unregister-ScheduledTaskByName {
    <#
    .SYNOPSIS
        Remove uma tarefa agendada por nome.
    .PARAMETER TaskName
        Nome da tarefa (ou busca parcial).
    .PARAMETER TaskPath
        Caminho da pasta (opcional).
    .PARAMETER Confirm
        Pede confirmacao antes de remover (padrao: true).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath,

        [switch]$Confirm = $true
    )

    $task = Resolve-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    if (-not $task) { throw "Tarefa '$TaskName' nao encontrada." }

    if ($PSCmdlet.ShouldProcess($task.TaskName, 'Remover tarefa agendada')) {
        if ($Confirm) {
            $response = Read-Host "Confirmar remocao da tarefa '$($task.TaskName)'? (S/N)"
            if ($response -notmatch '^[SsYy]') {
                Write-Output "Operacao cancelada."
                return
            }
        }
        $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
        Write-Output "Tarefa '$($task.TaskName)' removida."
    }
}
