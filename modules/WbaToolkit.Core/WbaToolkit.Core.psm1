Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path -LiteralPath $privatePath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path -LiteralPath $publicPath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
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
    'Export-ToolkitDocumentation',
    'New-ToolkitElevationCommand',
    'Get-ReportLogoBase64',
    'New-ToolkitHtmlReport',
    'Get-FileHashSha256',
    'New-ToolkitArchive',
    'Show-Spinner'
)
