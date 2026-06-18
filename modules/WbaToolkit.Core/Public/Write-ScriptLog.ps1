function Write-ScriptLog {
    <#
    .SYNOPSIS
        Registra uma mensagem de log com timestamp e nivel de severidade.

    .DESCRIPTION
        Formata e emite uma entrada de log com timestamp no formato
        'yyyy-MM-dd HH:mm:ss [LEVEL] mensagem'. Quando LogPath for informado,
        a entrada e gravada no arquivo de log. O nivel tambem controla a saida
        no console: WARN usa Write-Warn, ERROR usa Write-Fail, INFO usa Write-Info.

    .PARAMETER Message
        Mensagem a registrar.

    .PARAMETER Level
        Nivel de severidade: INFO (padrao), WARN ou ERROR.

    .PARAMETER LogPath
        Caminho completo do arquivo de log. Quando omitido, apenas emite no console.

    .EXAMPLE
        Write-ScriptLog -Message 'Iniciando coleta de dados.'

        Registra uma mensagem INFO sem gravar em arquivo.

    .EXAMPLE
        Write-ScriptLog -Message 'Gateway inacessivel.' -Level WARN -LogPath $session.LogsPath\diag.log

        Registra um aviso no console e no arquivo de log informado.

    .EXAMPLE
        Write-ScriptLog -Message 'Falha critica.' -Level ERROR -LogPath $logPath

        Registra um erro critico no console via Write-Fail e no arquivo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [string]$LogPath
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        try {
            $line | Add-Content -LiteralPath $LogPath
        }
        catch {
            Write-Verbose "Write-ScriptLog: nao foi possivel gravar em '$LogPath'. $($_.Exception.Message)"
        }
    }

    switch ($Level) {
        'WARN'  { Write-Warn  $Message }
        'ERROR' { Write-Fail  $Message }
        default { Write-Info  $Message }
    }
}
