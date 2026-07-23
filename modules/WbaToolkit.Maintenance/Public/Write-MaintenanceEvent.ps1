function Write-MaintenanceEvent {
    <#
    .SYNOPSIS
        Registra evento no Visualizador de Eventos do Windows.

    .DESCRIPTION
        Registra automaticamente a fonte de eventos quando necessario e escreve o
        evento no log Application. Nao lanca excecao em caso de falha; emite aviso
        em vez disso.

    .PARAMETER Source
        Nome da fonte de eventos (application source) a ser usada.

    .PARAMETER EventId
        Identificador numerico do evento.

    .PARAMETER Message
        Mensagem a ser registrada no evento.

    .PARAMETER EntryType
        Tipo de entrada: Information, Warning ou Error. Padrao: Information.

    .EXAMPLE
        Write-MaintenanceEvent -Source 'MeuScript' -EventId 1001 -Message 'Operacao concluida.'

    .NOTES
        Autor: wbaamaral
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [int]$EventId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$EntryType = 'Information'
    )

    try {
        Register-MaintenanceEventSource -Source $Source
        Write-EventLog -LogName Application -Source $Source `
            -EventId $EventId -EntryType $EntryType -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Warning "Nao foi possivel gravar evento '$Source' (ID $EventId): $($_.Exception.Message)"
    }
}
