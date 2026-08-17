# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxHoraSistema {
    <#
    .SYNOPSIS
        Checagem de saude: hora do sistema sincronizada (W32Time).

    .DESCRIPTION
        AVISO se o servico de horario nao responder ou nao registrar
        sincronizacao recente/bem-sucedida.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param()

    $result = Get-DropboxTimeSyncStatus
    $output = [string]$result.Output

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
        return New-DropboxCheckResult -Categoria 'Sistema' -Nome 'Hora do sistema' -Status 'AVISO' `
            -Detalhe 'O servico de horario (W32Time) nao respondeu ou nao esta em execucao.' `
            -Recomendacao 'Execute scripts/sincronizar-relogio.ps1.' -Penalidade 10
    }

    if ($output -match '(?i)last successful sync time:\s*(unspecified|n/a|nunca)') {
        return New-DropboxCheckResult -Categoria 'Sistema' -Nome 'Hora do sistema' -Status 'AVISO' `
            -Detalhe 'Nenhuma sincronizacao de hora bem-sucedida foi registrada.' `
            -Recomendacao 'Execute scripts/sincronizar-relogio.ps1.' -Penalidade 10
    }

    return New-DropboxCheckResult -Categoria 'Sistema' -Nome 'Hora do sistema' -Status 'OK' `
        -Detalhe 'Servico de horario em execucao com sincronizacao registrada.'
}
