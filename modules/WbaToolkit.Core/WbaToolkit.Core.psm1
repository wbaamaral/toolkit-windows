[CmdletBinding()]
param()

$publicPath  = Join-Path $PSScriptRoot 'Public'
$privatePath = Join-Path $PSScriptRoot 'Private'

Get-ChildItem -Path $publicPath, $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object {
        . $_.FullName
    }

Export-ModuleMember -Function @(
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
