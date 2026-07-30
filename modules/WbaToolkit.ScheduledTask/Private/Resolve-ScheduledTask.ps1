function Resolve-ScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath
    )

    $getParams = @{ TaskName = $TaskName }
    if ($TaskPath) { $getParams['TaskPath'] = $TaskPath }

    $task = Get-ScheduledTask @getParams -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $task) {
        $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
        $task = $allTasks | Where-Object {
            $_.TaskName -like "*$TaskName*" -or $_.TaskPath -like "*$TaskName*"
        } | Select-Object -First 1
    }

    $task
}
