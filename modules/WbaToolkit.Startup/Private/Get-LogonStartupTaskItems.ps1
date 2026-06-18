function Get-LogonStartupTaskItems {
    [CmdletBinding()]
    param()

    try {
        return @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            @($_.Triggers | Where-Object {
                $_.CimClass.CimClassName -in @('MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger')
            }).Count -gt 0
        } | ForEach-Object {
            $actionText = @($_.Actions | ForEach-Object {
                "$($_.Execute) $($_.Arguments)".Trim()
            }) -join '; '

            ConvertTo-StartupItem `
                -SourceType 'ScheduledTask' `
                -Scope 'TaskScheduler' `
                -Location $_.TaskPath `
                -Name ("$($_.TaskPath)$($_.TaskName)") `
                -ValueName $_.TaskName `
                -Command $actionText `
                -Enabled ([string]$_.State -ne 'Disabled')
        })
    }
    catch {
        return @([pscustomobject]@{
            Id              = 'erro'
            Name            = 'Erro ao consultar tarefas de inicializacao'
            SourceType      = 'ScheduledTask'
            Scope           = 'TaskScheduler'
            Location        = $null
            ValueName       = $null
            Command         = $_.Exception.Message
            Enabled         = $false
            State           = 'Erro'
            ManagedDisabled = $false
            BackupPath      = $null
            CanDisable      = $false
            CanEnable       = $false
            CanRemove       = $false
        })
    }
}
