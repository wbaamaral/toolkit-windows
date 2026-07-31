@{
    RootModule        = 'WbaToolkit.ScheduledTask.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c4d5e6f7-a890-1234-c4d5-e6f7a8901234'
    Author            = 'wbaamaral'
    CompanyName       = 'WBA'
    Copyright         = '(c) 2026 wbaamaral. Todos os direitos reservados.'
    Description       = 'Gerenciamento completo de tarefas agendadas do Windows (Task Scheduler).'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-ScheduledTaskDetail'
        'Find-ScheduledTask'
        'Get-ScheduledTaskSummary'
        'Enable-ScheduledTaskByName'
        'Disable-ScheduledTaskByName'
        'Unregister-ScheduledTaskByName'
        'Start-ScheduledTaskByName'
        'Export-ScheduledTaskXml'
        'Import-ScheduledTaskXml'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('ScheduledTask', 'TaskScheduler', 'Automation', 'Windows')
            ProjectUri = ''
        }
    }
}
