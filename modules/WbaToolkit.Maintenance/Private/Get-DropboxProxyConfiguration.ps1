# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxProxyConfiguration {
    <#
    .SYNOPSIS
        Consulta a configuracao de proxy do WinHTTP no sistema.

    .DESCRIPTION
        Fronteira isolada e mockavel sobre 'netsh winhttp show proxy', executado via
        Invoke-ExternalCommand (WbaToolkit.Core).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com ExitCode e Output, conforme Invoke-ExternalCommand.
    #>
    [CmdletBinding()]
    param()

    return Invoke-ExternalCommand -FilePath 'netsh' -ArgumentList @('winhttp', 'show', 'proxy')
}
