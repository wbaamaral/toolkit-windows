function Remove-BackupAntigo {
    <#
    .SYNOPSIS
        Remove backups antigos por retencao.
    .DESCRIPTION
        Remove sessoes de backup mais antigas que o periodo especificado.

        Uma sessao de backup e um diretorio que contem 'metadados.json' com
        'CreatedAt' legivel. O layout gravado por Backup-UserData e
        <BackupRoot>\<modulo>\<ddMMyyyy_HHmmss>\metadados.json; sessoes legadas
        diretamente em <BackupRoot>\<sessao> tambem sao reconhecidas.

        Diretorios sem metadados validos (por exemplo, o conteiner <modulo>)
        NUNCA sao removidos: a idade so e decidida a partir dos metadados.
    .PARAMETER Days
        Dias de retencao. Backups mais antigos serao removidos.
    .PARAMETER BackupRoot
        Diretorio raiz dos backups. Se omitido, usa o configurado.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [int]$Days,

        [string]$BackupRoot
    )

    if (-not $BackupRoot) {
        $config = Get-BackupConfiguration
        if ($config -and $config.UserBackup.LocalBackupPath) {
            $BackupRoot = [System.Environment]::ExpandEnvironmentVariables($config.UserBackup.LocalBackupPath)
        } else {
            $BackupRoot = 'C:\WBA\Backups'
        }
    }

    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) { Write-Warning "Diretorio de backups nao encontrado: $BackupRoot"; return }

    # Le CreatedAt do metadados.json. No Windows PowerShell 5.1, ConvertTo-Json de
    # Get-Date grava um objeto {value, DisplayHint, DateTime}; versoes recentes gravam
    # uma string ISO 8601. Retorna $null quando nao for possivel determinar a data.
    $getCreatedAt = {
        param([string]$SessionDir)
        $metaPath = Join-Path $SessionDir 'metadados.json'
        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { return $null }
        try {
            $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $raw = $meta.CreatedAt
            if ($null -eq $raw) { return $null }
            if ($raw -is [datetime]) { return $raw }
            if ($raw.PSObject.Properties['value']) { $raw = $raw.value }
            if ($raw -is [datetime]) { return $raw }
            return [datetime]::Parse([string]$raw, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            Write-Verbose "Metadados ilegiveis em '$metaPath'; sessao ignorada: $($_.Exception.Message)"
            return $null
        }
    }

    # Descobre sessoes: filho direto com metadados e uma sessao legada (nao desce nela);
    # filho direto sem metadados e um conteiner de modulo cujos filhos podem ser sessoes.
    $sessions = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($child in @(Get-ChildItem -LiteralPath $BackupRoot -Directory)) {
        $createdAt = & $getCreatedAt $child.FullName
        if ($null -ne $createdAt) {
            $sessions.Add([pscustomobject]@{ Path = $child.FullName; CreatedAt = $createdAt })
            continue
        }
        foreach ($grandChild in @(Get-ChildItem -LiteralPath $child.FullName -Directory)) {
            $createdAt = & $getCreatedAt $grandChild.FullName
            if ($null -ne $createdAt) {
                $sessions.Add([pscustomobject]@{ Path = $grandChild.FullName; CreatedAt = $createdAt })
            }
            else {
                Write-Verbose "Sem metadados validos; mantido: $($grandChild.FullName)"
            }
        }
    }

    $cutoff = (Get-Date).AddDays(-$Days)
    $oldBackups = @($sessions | Where-Object { $_.CreatedAt -lt $cutoff })

    if ($oldBackups.Count -eq 0) { Write-Output "Nenhum backup antigo encontrado (>$Days dias)."; return }

    if ($PSCmdlet.ShouldProcess("$($oldBackups.Count) backup(s) antigo(s) em $BackupRoot", 'Remover')) {
        $removed = 0
        $failed  = 0
        foreach ($session in $oldBackups) {
            try {
                Remove-Item -LiteralPath $session.Path -Recurse -Force -ErrorAction Stop
                $removed++
            }
            catch {
                $failed++
                Write-Warning "Falha ao remover '$($session.Path)': $($_.Exception.Message)"
            }
        }
        Write-Output "$removed backup(s) antigo(s) removido(s)."
        if ($failed -gt 0) { Write-Warning "$failed backup(s) antigo(s) nao puderam ser removidos." }
    }
}
