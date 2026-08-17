# Projeto: wba-toolkit
# Autor: wbaamaral

function Restart-DropboxProcess {
    <#
    .SYNOPSIS
        Reinicia o processo do cliente Dropbox.

    .DESCRIPTION
        Captura o caminho do executavel em execucao ANTES de parar o processo
        (Stop-Process nao expoe mais o Path depois). Se o processo nao estiver
        em execucao, informa que nao ha o que reiniciar em vez de tratar como
        erro fatal. Sem confirmacao interna -- e responsabilidade do script
        wrapper confirmar com o operador antes de chamar esta funcao.

    .EXAMPLE
        Restart-DropboxProcess

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com Success, Restarted e Message.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $processes = @(Get-DropboxProcessInfo)

    if ($processes.Count -eq 0) {
        return [pscustomobject]@{
            Success   = $true
            Restarted = $false
            Message   = 'Nenhum processo Dropbox em execucao; nada para reiniciar.'
        }
    }

    $exePath = $processes[0].Path

    try {
        Stop-Process -Name 'Dropbox' -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            Success   = $false
            Restarted = $false
            Message   = "Falha ao parar o processo Dropbox: $($_.Exception.Message)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($exePath) -or -not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        return [pscustomobject]@{
            Success   = $false
            Restarted = $false
            Message   = 'Processo parado, mas o executavel do Dropbox nao pode ser localizado para reinicio automatico.'
        }
    }

    try {
        Start-Process -FilePath $exePath | Out-Null
        return [pscustomobject]@{
            Success   = $true
            Restarted = $true
            Message   = "Processo Dropbox reiniciado ($exePath)."
        }
    }
    catch {
        return [pscustomobject]@{
            Success   = $false
            Restarted = $false
            Message   = "Processo parado, mas falha ao reiniciar: $($_.Exception.Message)"
        }
    }
}
