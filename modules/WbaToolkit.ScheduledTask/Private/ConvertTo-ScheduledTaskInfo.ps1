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
            Argument = $_.Arguments
            WorkDir  = $_.WorkingDirectory
        }
    }

    $triggers = $Task.Triggers | ForEach-Object {
        # CimInstance nao tem a propriedade CimClassName; a classe fica em CimClass.CimClassName.
        $triggerClass = $_.CimClass.CimClassName
        $trig = [pscustomobject]@{
            Type       = $triggerClass
            Enabled    = $_.Enabled
        }
        if ($triggerClass -eq 'MSFT_TaskTimeTrigger') {
            $trig | Add-Member -NotePropertyName 'StartBoundary' -NotePropertyValue $_.StartBoundary -Force
            if ($_.Repetition.Interval) {
                $trig | Add-Member -NotePropertyName 'Interval' -NotePropertyValue $_.Repetition.Interval -Force
            }
        }
        if ($triggerClass -eq 'MSFT_TaskBootTrigger') {
            $trig | Add-Member -NotePropertyName 'Delay' -NotePropertyValue $_.Delay -Force
        }
        if ($triggerClass -eq 'MSFT_TaskLogonTrigger') {
            $trig | Add-Member -NotePropertyName 'UserId' -NotePropertyValue $_.UserId -Force
        }
        $trig
    }

    [pscustomobject]@{
        TaskName    = $Task.TaskName
        TaskPath    = $Task.TaskPath
        State       = [string]$Task.State
        Description = $Task.Description
        Author      = $Task.Author
        RunAs       = if ($Task.Principal.UserId) { $Task.Principal.UserId } elseif ($Task.Principal.GroupId) { $Task.Principal.GroupId } else { 'SYSTEM' }
        RunLevel    = [string]$Task.Principal.RunLevel
        LogonType   = [string]$Task.Principal.LogonType
        Enabled     = $Task.Settings.Enabled
        AllowDemand  = $Task.Settings.AllowDemandStart
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
