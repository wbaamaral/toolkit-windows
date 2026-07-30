function Find-ScheduledTask {
    <#
    .SYNOPSIS
        Busca tarefas agendadas por nome, caminho ou descricao.
    .DESCRIPTION
        Suporta busca parcial com curingas. Retorna lista de tarefas encontradas.
    .PARAMETER SearchTerm
        Termo de busca (parcial ou exato).
    .PARAMETER TaskPath
        Caminho da pasta para filtrar (ex: \Microsoft\Windows\).
    .PARAMETER State
        Filtrar por estado: Ready, Running, Disabled.
    .OUTPUTS
        Lista de PSCustomObject.
    #>
    [CmdletBinding()]
    param(
        [string]$SearchTerm,
        [string]$TaskPath,
        [ValidateSet('Ready', 'Running', 'Disabled', 'All')]
        [string]$State = 'All'
    )

    $getParams = @{}
    if ($TaskPath) { $getParams['TaskPath'] = $TaskPath }

    $tasks = Get-ScheduledTask @getParams -ErrorAction SilentlyContinue

    if ($State -ne 'All') {
        $tasks = $tasks | Where-Object { $_.State.ToString() -eq $State }
    }

    if ($SearchTerm) {
        $tasks = $tasks | Where-Object {
            $_.TaskName -like "*$SearchTerm*" -or
            $_.TaskPath -like "*$SearchTerm*" -or
            $_.Description -like "*$SearchTerm*"
        }
    }

    $tasks | ForEach-Object {
        ConvertTo-ScheduledTaskInfo -Task $_
    }
}
