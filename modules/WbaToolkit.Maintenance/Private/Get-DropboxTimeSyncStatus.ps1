# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxTimeSyncStatus {
    <#
    .SYNOPSIS
        Consulta o status do servico de sincronizacao de hora do Windows (W32Time).

    .DESCRIPTION
        Fronteira isolada e mockavel sobre 'w32tm /query /status', executado via
        Invoke-ExternalCommand (WbaToolkit.Core).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com ExitCode e Output, conforme Invoke-ExternalCommand.
    #>
    [CmdletBinding()]
    param()

    return Invoke-ExternalCommand -FilePath 'w32tm' -ArgumentList @('/query', '/status')
}
