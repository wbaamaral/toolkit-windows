function ConvertTo-ScheduledTaskInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Task
    )

    $info = Get-ScheduledTaskInfo -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction SilentlyContinue

    $actions = $Task.Actions | ForEach-Object {
        [pscustomobject]@{
            Execute  = $_.Execute
            Argument = $_.Argument
            WorkDir  = $_.WorkingDirectory
        }
    }

    $triggers = $Task.Triggers | ForEach-Object {
        $trig = [pscustomobject]@{
            Type       = $_.CimClass.CimClassName
            Enabled    = $_.Enabled
        }
        if ($_.CimClassName -eq 'MSFT_TaskTimeTrigger') {
            $trig | Add-Member -NotePropertyName 'StartBoundary' -NotePropertyValue $_.StartBoundary -Force
            if ($_.Repetition.Interval) {
                $trig | Add-Member -NotePropertyName 'Interval' -NotePropertyValue $_.Repetition.Interval -Force
            }
        }
        if ($_.CimClassName -eq 'MSFT_TaskBootTrigger') {
            $trig | Add-Member -NotePropertyName 'Delay' -NotePropertyValue $_.Delay -Force
        }
        if ($_.CimClassName -eq 'MSFT_TaskLogonTrigger') {
            $trig | Add-Member -NotePropertyName 'UserId' -NotePropertyValue $_.UserId -Force
        }
        $trig
    }

    [pscustomobject]@{
        TaskName    = $Task.TaskName
        TaskPath    = $Task.TaskPath
        State       = $Task.State.ToString()
        Description = $Task.Description
        Author      = $Task.Author
        RunAs       = if ($Task.Principal.UserId) { $Task.Principal.UserId } else { 'SYSTEM' }
        RunLevel    = $Task.Principal.RunLevel.ToString()
        LogonType   = $Task.Principal.LogonType.ToString()
        Enabled     = $Task.Settings.Enabled
        AllowDemand  = $Task.Settings.AllowStartIfOnBatteries
        DisallowNew  = $Task.Settings.DisallowStartIfOnBatteries
        ExecutionTimeLimit = $Task.Settings.ExecutionTimeLimit
        LastRunTime = if ($info) { $info.LastRunTime } else { $null }
        LastResult  = if ($info) { $info.LastTaskResult } else { $null }
        NextRunTime = if ($info) { $info.NextRunTime } else { $null }
        MissedRuns  = if ($info) { $info.NumberOfMissedRuns } else { $null }
        Actions     = $actions
        Triggers    = $triggers
    }
}
