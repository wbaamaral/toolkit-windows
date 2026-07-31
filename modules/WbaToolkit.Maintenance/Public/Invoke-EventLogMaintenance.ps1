function Invoke-EventLogMaintenance {
    <#
    .SYNOPSIS
        Limpa logs do Visualizador de Eventos com opcoes de backup de erros.

    .DESCRIPTION
        Processa os logs Application, System e Setup de acordo com a acao escolhida.
        Em modo ErrorOnly, exporta eventos de erro/falha para arquivo .evtx em
        BackupPath antes de limpar. Em modo All, limpa sem backup. Em modo None,
        nao efetua nenhuma alteracao.

    .PARAMETER Action
        All       : limpa todos os eventos dos logs alvo.
        ErrorOnly : exporta erros/falhas para backup e limpa.
        None      : nao efetua limpeza (padrao; ideal para automacao).
        Ask       : pergunta interativamente ao operador.

    .PARAMETER BackupPath
        Diretorio onde serao salvos os arquivos .evtx de backup (modo ErrorOnly).

    .PARAMETER EventSource
        Nome da fonte de eventos para registro no Visualizador de Eventos.
        Padrao: LimpezaWindows.

    .EXAMPLE
        Invoke-EventLogMaintenance -Action None

    .EXAMPLE
        Invoke-EventLogMaintenance -Action ErrorOnly -BackupPath 'C:\WBA\Relatorios\logs'

    .EXAMPLE
        Invoke-EventLogMaintenance -Action Ask -BackupPath $session.LogsPath

    .NOTES
        Autor: wbaamaral
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Ask', 'All', 'ErrorOnly', 'None')]
        [string]$Action = 'None',

        [Parameter()]
        [string]$BackupPath = '',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$EventSource = 'LimpezaWindows'
    )

    $targetLogs = @('Application', 'System', 'Setup')

    if ($Action -eq 'Ask') {
        Write-Host ""
        Write-Host "Limpeza do Visualizador de Eventos — logs: $($targetLogs -join ', ')" -ForegroundColor Cyan
        $ts = Get-Date -Format 'dd/MM/yyyy HH:mm'
        Write-Host "  [1] Limpar TODOS os eventos ate $ts"
        Write-Host "  [2] Limpar apenas logs com eventos de falha/erro (backup em $BackupPath)"
        Write-Host "  [3] Nao efetuar limpeza de eventos" -ForegroundColor Green
        Write-Host ""
        $choice = $null
        try {
            do { $choice = Read-Host "Escolha [1/2/3]" } while ((-not [string]::IsNullOrEmpty($choice)) -and ($choice -notmatch '^[123]$'))
        } catch { $choice = $null }
        $map = @{ '1' = 'All'; '2' = 'ErrorOnly'; '3' = 'None' }
        $Action = if ($choice -and $map.ContainsKey($choice)) { $map[$choice] } else { 'None' }
    }

    switch ($Action) {
        'All' {
            foreach ($log in $targetLogs) {
                try {
                    Write-Host "Executando: Limpar log de eventos '$log'" -ForegroundColor Green
                    wevtutil.exe cl $log 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        throw "wevtutil cl retornou codigo $LASTEXITCODE"
                    }
                    Write-Host "Log '$log' limpo." -ForegroundColor Green
                }
                catch {
                Write-Fail "Falha ao limpar log '$log': $($_.Exception.Message)"
                    Write-Warning "ERRO ao limpar '$log': $($_.Exception.Message)"
                }
            }
            $msg = "$EventSource limpou logs: $($targetLogs -join ', ') em $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')."
            Write-MaintenanceEvent -Source $EventSource -EventId 1002 -Message $msg
        }
        'ErrorOnly' {
            $cleaned = @()
            foreach ($log in $targetLogs) {
                try {
                    $filter   = @{ LogName = $log; Level = @(1, 2) }
                    $hasErrors = Get-WinEvent -FilterHashtable $filter -MaxEvents 1 -ErrorAction SilentlyContinue
                    if (-not $hasErrors) {
                Write-Info "Log '$log': sem eventos de erro/falha - ignorado."
                        continue
                    }
                    $ts     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
                    $backup = Join-Path $BackupPath "eventos-$log-$ts.evtx"
            Write-Info "Exportando erros de '$log' e limpando o log."
                    wevtutil.exe epl $log $backup "/q:*[System[Level<=2]]" 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        throw "wevtutil epl retornou codigo $LASTEXITCODE — backup nao foi criado, log '$log' NAO sera limpo"
                    }
                    wevtutil.exe cl $log 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        throw "wevtutil cl retornou codigo $LASTEXITCODE apos backup em $backup"
                    }
                Write-Ok "Log '$log' limpo. Backup de erros: $backup"
                    $cleaned += $log
                }
                catch {
                Write-Fail "Falha ao processar log '$log': $($_.Exception.Message)"
                    Write-Warning "ERRO ao processar '$log': $($_.Exception.Message)"
                }
            }
            if ($cleaned.Count -gt 0) {
                $msg = "$EventSource limpou logs com erros: $($cleaned -join ', ') em " +
                       "$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss'). Backups em: $BackupPath."
                Write-MaintenanceEvent -Source $EventSource -EventId 1003 -Message $msg
            }
        }
        'None' {
            Write-Host "Limpeza do Visualizador de Eventos ignorada." -ForegroundColor DarkGray
        }
    }
}
