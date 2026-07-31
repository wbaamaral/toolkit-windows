function Set-SshdConfig {
    <#
    .SYNOPSIS
        Altera diretrizes do sshd_config com backup automatico.

    .DESCRIPTION
        Modifica uma ou mais diretrizes no sshd_config. Cria backup do arquivo
        antes de alterar. Nao reinicia o servico automaticamente (use Restart-Service sshd).

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
    [CmdletBinding()]
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

    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    $newLines = [System.Collections.Generic.List[string]]::new()
    $applied = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        $matched = $false

        foreach ($key in $Settings.Keys) {
            if ($trimmed -match "^$([regex]::Escape($key))\s+" -or $trimmed -eq $key) {
                if ($null -eq $Settings[$key]) {
                    $removed.Add($key)
                    $matched = $true
                    break
                }
                else {
                    $newLines.Add("$key $($Settings[$key])")
                    $applied.Add("$key = $($Settings[$key])")
                    $matched = $true
                    break
                }
            }
        }

        if (-not $matched) {
            $newLines.Add($line)
        }
    }

    foreach ($key in $Settings.Keys) {
        if ($null -ne $Settings[$key] -and -not $applied.Contains("$key = $($Settings[$key])")) {
            $newLines.Add("$key $($Settings[$key])")
            $applied.Add("$key = $($Settings[$key])")
        }
    }

    try {
        $newLines | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Copy-Item -LiteralPath $backupPath -Destination $Path -Force
        return [pscustomobject]@{
            Success         = $false
            Message         = "Falha ao gravar config: $($_.Exception.Message). Backup restaurado."
            BackupPath      = $backupPath
            RestartRequired = $false
        }
    }

    $restartRequired = $applied.Count -gt 0 -or $removed.Count -gt 0

    [pscustomobject]@{
        Success         = $true
        Message         = "Aplicadas: $($applied.Count) | Removidas: $($removed.Count)"
        Applied         = $applied.ToArray()
        Removed         = $removed.ToArray()
        BackupPath      = $backupPath
        RestartRequired = $restartRequired
    }
}
