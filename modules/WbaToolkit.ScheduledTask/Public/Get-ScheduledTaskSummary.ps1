function Get-ScheduledTaskSummary {
    <#
    .SYNOPSIS
        Retorna resumo geral das tarefas agendadas.
    .DESCRIPTION
        Contagem total, habilitadas, desabilitadas, por estado, e ultimas execucoes.
    .OUTPUTS
        PSCustomObject com totais e estatisticas.
    #>
    [CmdletBinding()]
    param()

    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue

    $summary = [pscustomobject]@{
        Total          = ($allTasks | Measure-Object).Count
        Enabled        = ($allTasks | Where-Object { $_.Settings.Enabled }).Count
        Disabled       = ($allTasks | Where-Object { -not $_.Settings.Enabled }).Count
        Ready          = ($allTasks | Where-Object { $_.State -eq 'Ready' }).Count
        Running        = ($allTasks | Where-Object { $_.State -eq 'Running' }).Count
        ByState        = $allTasks | Group-Object State | ForEach-Object {
            [pscustomobject]@{ State = $_.Name; Count = $_.Count }
        }
        TopPaths       = $allTasks | Group-Object TaskPath | Sort-Object Count -Descending |
            Select-Object -First 10 | ForEach-Object {
                [pscustomobject]@{ Path = $_.Name; Count = $_.Count }
            }
        RecentFailures = $allTasks | ForEach-Object {
            $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
            if ($info -and $info.LastTaskResult -ne 0 -and $info.LastRunTime) {
                [pscustomobject]@{
                    TaskName   = $_.TaskName
                    TaskPath   = $_.TaskPath
                    LastResult = $info.LastTaskResult
                    LastRun    = $info.LastRunTime
                }
            }
        } | Where-Object { $_ } | Sort-Object LastRun -Descending | Select-Object -First 10
    }

    $summary
}
