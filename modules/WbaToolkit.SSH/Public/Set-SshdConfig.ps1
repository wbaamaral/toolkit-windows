function Set-SshdConfig {
    <#
    .SYNOPSIS
        Altera diretrizes do sshd_config com backup automatico.

    .DESCRIPTION
        Modifica uma ou mais diretrizes no sshd_config. Cria backup do arquivo
        antes de alterar. Diretivas sao aplicadas so na secao global (antes do primeiro
        Match), o arquivo e gravado em UTF-8 sem BOM e validado com sshd -t; se a
        validacao falhar, o backup e restaurado. Nao reinicia o servico (use Restart-Service sshd).

    .PARAMETER Settings
        Hashtable com pares chave-valor para definir/excluir.
        Para excluir uma chave: @{ 'Port' = $null }

    .PARAMETER Path
        Caminho do sshd_config. Padrao: %programdata%\ssh\sshd_config.

    .OUTPUTS
        PSCustomObject com: Success, Message, BackupPath, RestartRequired.

    .EXAMPLE
        Set-SshdConfig -Settings @{ 'Port' = '2222'; 'PasswordAuthentication' = 'no' }

    .EXAMPLE
        Set-SshdConfig -Settings @{ 'PermitRootLogin' = $null }
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $paths = Get-SshConfigPath
        $Path = $paths.SshdConfig
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Success         = $false
            Message         = "Arquivo nao encontrado: $Path"
            BackupPath      = $null
            RestartRequired = $false
        }
    }

    $backupDir = Split-Path -Parent $Path
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $backupPath = Join-Path $backupDir "sshd_config.bak.$timestamp"

    if (-not $PSCmdlet.ShouldProcess($Path, 'Alterar configuracao do servidor SSH')) {
        return [pscustomobject]@{
            Success = $true; Message = 'Alteracao de configuracao ignorada por WhatIf.'
            BackupPath = $null; RestartRequired = $false
        }
    }

    try {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
        Write-Verbose "Backup criado: $backupPath"
    }
    catch {
        return [pscustomobject]@{
            Success         = $false
            Message         = "Falha ao criar backup: $($_.Exception.Message)"
            BackupPath      = $null
            RestartRequired = $false
        }
    }

    $raw = [System.IO.File]::ReadAllText($Path)
    $newline = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = @($raw -split "`r?`n")
    if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -SkipLast 1) }

    # Diretivas globais so valem antes do primeiro 'Match': o sshd_config padrao do Windows
    # termina em 'Match Group administrators', e qualquer linha depois dele pertence ao bloco.
    $matchIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^Match(\s|$)') { $matchIndex = $i; break }
    }
    $globalEnd = if ($matchIndex -ge 0) { $matchIndex } else { $lines.Count }

    $newLines = [System.Collections.Generic.List[string]]::new()
    $applied = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    $handled = @{}

    for ($i = 0; $i -lt $globalEnd; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()
        $matched = $false

        foreach ($key in $Settings.Keys) {
            if ($trimmed -match "^$([regex]::Escape($key))(\s|$)") {
                $matched = $true
                if ($null -eq $Settings[$key]) {
                    $removed.Add($key)
                }
                elseif (-not $handled.ContainsKey($key)) {
                    # sshd usa a primeira ocorrencia; duplicatas globais sao descartadas.
                    $newLines.Add("$key $($Settings[$key])")
                    $applied.Add("$key = $($Settings[$key])")
                }
                $handled[$key] = $true
                break
            }
        }

        if (-not $matched) {
            $newLines.Add($line)
        }
    }

    foreach ($key in $Settings.Keys) {
        if ($null -ne $Settings[$key] -and -not $handled.ContainsKey($key)) {
            $newLines.Add("$key $($Settings[$key])")
            $applied.Add("$key = $($Settings[$key])")
        }
    }

    for ($i = $globalEnd; $i -lt $lines.Count; $i++) {
        $newLines.Add($lines[$i])
    }

    $restoreBackup = {
        try { Copy-Item -LiteralPath $backupPath -Destination $Path -Force -ErrorAction Stop; 'Backup restaurado.' }
        catch { "Falha ao restaurar o backup ($backupPath): $($_.Exception.Message)" }
    }

    try {
        # UTF-8 sem BOM: o sshd do OpenSSH para Windows nao aceita BOM no sshd_config.
        $content = ($newLines -join $newline) + $newline
        [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        $restoreMessage = & $restoreBackup
        return [pscustomobject]@{
            Success         = $false
            Message         = "Falha ao gravar config: $($_.Exception.Message). $restoreMessage"
            BackupPath      = $backupPath
            RestartRequired = $false
        }
    }

    $syntax = Test-SshdConfigSyntax -Path $Path
    if ($syntax.Available -and -not $syntax.Valid) {
        $restoreMessage = & $restoreBackup
        return [pscustomobject]@{
            Success         = $false
            Message         = "sshd -t rejeitou a configuracao: $($syntax.Output). $restoreMessage"
            BackupPath      = $backupPath
            RestartRequired = $false
        }
    }

    $restartRequired = $applied.Count -gt 0 -or $removed.Count -gt 0
    $message = "Aplicadas: $($applied.Count) | Removidas: $($removed.Count)"
    if (-not $syntax.Available) {
        $message += ' | Validacao sshd -t indisponivel (sshd.exe nao encontrado).'
    }

    [pscustomobject]@{
        Success         = $true
        Message         = $message
        Applied         = $applied.ToArray()
        Removed         = $removed.ToArray()
        BackupPath      = $backupPath
        RestartRequired = $restartRequired
        SyntaxValidated = [bool]$syntax.Available
    }
}
