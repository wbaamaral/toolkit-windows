@{
    RootModule        = 'WbaToolkit.Core.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = '6b7a86d1-0d50-4d3a-88f3-25ad0f0f58bc'
    Author            = 'wbaamaral'
    CompanyName       = 'wbaamaral'
    Copyright         = '(c) wbaamaral. All rights reserved.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Test-IsAdministrator',
        'Invoke-Safe',
        'Format-FileSize',
        'Write-Ok',
        'Write-Fail',
        'Write-Warn',
        'Write-Info',
        'Write-Title',
        'Write-Section',
        'Write-Step',
        'Read-YesNo',
        'Read-UserInput',
        'Invoke-ExternalCommand',
        'ConvertTo-HtmlSafe',
        'Get-Utf8BomEncoding',
        'Write-TextFileUtf8',
        'Write-ScriptLog',
        'Initialize-ScriptSession',
        'Get-CimInstanceSafe',
        'Get-ToolkitConfiguration',
        'Set-ToolkitReportsRoot',
        'Get-ToolkitReportsRoot',
        'Initialize-ToolkitReportSession',
        'Export-ToolkitFunctionDocs',
        'Export-ToolkitDocumentation'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
