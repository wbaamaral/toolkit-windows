function Invoke-FilesystemCheck {
    <#
    .SYNOPSIS
        Verifica eventos de falha no sistema de arquivos e oferece agendamento de chkdsk.

    .DESCRIPTION
        Consulta o log de eventos buscando falhas nos provedores de armazenamento
        nos ultimos 30 dias. Quando falhas sao detectadas, exibe um resumo e,
        conforme o parametro Action, agenda chkdsk no proximo boot ou apenas informa.

    .PARAMETER Action
        Ask      : pergunta interativamente ao operador.
        Schedule : agenda chkdsk automaticamente sem interacao.
        Skip     : exibe aviso mas nao agenda (padrao; ideal para automacao).

    .PARAMETER CallerScript
        Nome do script chamador, usado na mensagem de orientacao quando Action=Skip.

    .PARAMETER EventSource
        Nome da fonte de eventos para registro no Visualizador de Eventos.
        Padrao: LimpezaWindows.

    .EXAMPLE
        Invoke-FilesystemCheck -Action Ask -CallerScript 'limpar-windows.ps1'

    .EXAMPLE
        Invoke-FilesystemCheck -Action Schedule

    .NOTES
        Autor: wbaamaral
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Ask', 'Schedule', 'Skip')]
        [string]$Action = 'Skip',

        [Parameter()]
        [string]$CallerScript = '',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$EventSource = 'LimpezaWindows'
    )

    $fsEvents = Get-FilesystemErrorEvent
    $fsCount  = @($fsEvents).Count

    if ($fsCount -eq 0) {
        Write-Host "Sistema de arquivos: nenhum evento de falha detectado nos ultimos 30 dias." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "ATENCAO: $fsCount evento(s) de falha no sistema de arquivos (ultimos 30 dias):" -ForegroundColor Yellow
    @($fsEvents) | Select-Object TimeCreated, Id, ProviderName,
        @{N = 'Mensagem'; E = {
            $m = $_.Message -replace "`r`n", ' '
            if ($m.Length -gt 90) { $m.Substring(0, 90) + '...' } else { $m }
        }} | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host

    $schedule = $false

    switch ($Action) {
        'Ask' {
            Write-Host ""
            Write-Host "Deseja agendar chkdsk $env:SystemDrive /f /r para o proximo boot?" -ForegroundColor Yellow
            Write-Host "  [S] Sim — agendar chkdsk (requer reinicializacao)"
            Write-Host "  [N] Nao — ignorar e continuar" -ForegroundColor Green
            Write-Host ""
            do { $choice = Read-Host "Escolha [S/N]" } while ($choice -notmatch '^[SsNn]$')
            $schedule = $choice -match '^[Ss]$'
        }
        'Schedule' { $schedule = $true }
        default {
            Write-Host ""
            Write-Host "AVISO: Falhas detectadas. Para agendar verificacao use:" -ForegroundColor Yellow
            if ($CallerScript) {
                Write-Host "       .\$CallerScript -ChkdskAction Schedule" -ForegroundColor Yellow
            }
        }
    }

    if (-not $schedule) { return }

    try {
        Write-Host "Executando: Agendando chkdsk $env:SystemDrive /f /r" -ForegroundColor Green
        $output = cmd.exe /c "echo Y | chkdsk $env:SystemDrive /f /r" 2>&1
        $output | ForEach-Object { Write-Host "  $_" }
    }
    catch {
        Write-Host "Falha ao agendar chkdsk: $($_.Exception.Message)" -ForegroundColor Red
        Write-Warning "ERRO ao agendar chkdsk: $($_.Exception.Message)"
        return
    }

    $drv   = $env:SystemDrive
    $now   = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
    $evMsg = "$EventSource agendou verificacao de disco (CHKDSK) para o proximo reinicio.`r`n" +
             "Volume    : $drv`r`n" +
             "Parametros: chkdsk $drv /f /r`r`n" +
             "Motivo    : $fsCount evento(s) de falha no sistema de arquivos (ultimos 30 dias).`r`n" +
             "Data      : $now`r`n" +
             "Apos o reinicio com verificacao concluida, execute novamente este script."

    Write-MaintenanceEvent -Source $EventSource -EventId 1001 -Message $evMsg

    Write-Host ""
    Write-Host "chkdsk agendado. Evento registrado: Aplicativo > $EventSource > ID 1001." -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANTE: Reinicie o sistema para executar o chkdsk." -ForegroundColor Yellow
    Write-Host "Apos reiniciar, execute novamente este script para continuar a limpeza." -ForegroundColor Yellow
}
