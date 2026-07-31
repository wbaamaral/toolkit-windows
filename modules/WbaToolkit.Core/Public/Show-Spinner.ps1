function Show-Spinner {
    <#
    .SYNOPSIS
        Exibe um spinner com timer durante operacoes demoradas.

    .DESCRIPTION
        Mostra um animacao de spinner com contador de tempo enquanto uma operacao
        esta em execucao. Retorna o resultado da operacao.

    .PARAMETER Message
        Mensagem exibida ao lado do spinner.

    .PARAMETER ScriptBlock
        Bloco de codigo a ser executado.

    .EXAMPLE
        $result = Show-Spinner -Message "Testando conectividade" -ScriptBlock { Start-Sleep -Seconds 3; return "OK" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock
    )

    $frames = '|', '/', '-', '\'
    $i = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Mostrar spinner imediatamente antes de iniciar o job
    Write-Host "`r| $Message [00:00:00]" -NoNewline -ForegroundColor Cyan

    # Executar script em job para nao bloquear o spinner
    $job = Start-Job -ScriptBlock $ScriptBlock

    while (-not $job.HasExited) {
        $elapsed = $stopwatch.Elapsed
        $ts = '{0:00}:{1:00}:{2:00}' -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds
        $frame = $frames[$i % 4]
        Write-Host "`r$frame $Message [$ts]" -NoNewline -ForegroundColor Cyan
        $i++
        Start-Sleep -Milliseconds 200
    }

    $stopwatch.Stop()
    $result = Receive-Job -Job $job
    Remove-Job -Job $job -Force

    # Limpar linha do spinner
    $clearLen = $Message.Length + 20
    Write-Host ("`r" + (' ' * $clearLen) + "`r") -NoNewline

    return $result
}
