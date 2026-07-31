function Export-BackupReport {
    <#
    .SYNOPSIS
        Gera relatorio de backup e restore points.
    .DESCRIPTION
        Exporta relatorio consolidado em JSON, TXT ou HTML.
    .PARAMETER Format
        Formato de saida: JSON, TXT, HTML.
    .PARAMETER OutputPath
        Caminho do arquivo de saida. Se omitido, gera na pasta de relatorios.
    .OUTPUTS
        Caminho do arquivo gerado.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('JSON', 'TXT', 'HTML')]
        [string]$Format = 'JSON',

        [string]$OutputPath
    )

    $health = Test-VssHealth
    $restorePoints = Get-RestorePointInfo
    $history = Get-BackupHistory
    $config = Get-BackupConfiguration

    $report = [pscustomobject]@{
        GeneratedAt    = Get-Date
        ComputerName   = $env:COMPUTERNAME
        Health         = $health
        RestorePoints  = @($restorePoints)
        BackupHistory  = @($history)
        Configuration  = $config
    }

    if (-not $OutputPath) {
        $timestamp = Get-Date -Format 'ddMMyyyy_HHmmss'
        $ext = switch ($Format) { 'JSON' { '.json' }; 'TXT' { '.txt' }; 'HTML' { '.html' } }
        $OutputPath = Join-Path "C:\WBA\Relatorios\backup" "$timestamp$ext"
        $outputDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
    }

    switch ($Format) {
        'JSON' {
            $report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
        }
        'TXT' {
            $lines = New-Object 'System.Collections.Generic.List[string]'
            $lines.Add('WBA Windows Toolkit - Relatorio de Backup')
            $lines.Add(('Gerado em       : {0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
            $lines.Add(('Computador       : {0}' -f $env:COMPUTERNAME))
            $lines.Add('')
            $lines.Add('--- Saude do Sistema ---')
            foreach ($check in $health.Checks) {
                $lines.Add(('  [{0}] {1}: {2}' -f $check.Status, $check.Name, $check.Detail))
            }
            $lines.Add('')
            $lines.Add("--- Restore Points ($($restorePoints.Count) encontrado(s)) ---")
            foreach ($rp in $restorePoints) {
                $lines.Add(('  #{0} - {1} ({2})' -f $rp.SequenceNumber, $rp.Description, $rp.CreationTime))
            }
            $lines.Add('')
            $lines.Add("--- Historico de Backups ($($history.Count) encontrado(s)) ---")
            foreach ($h in $history) {
                $status = if ($h.AllSuccess) { 'OK' } else { 'FALHA' }
                $lines.Add(('  [{0}] {1} - {2}' -f $status, $h.CreatedAt, $h.BackupPath))
            }
            $lines | Set-Content -Path $OutputPath -Encoding UTF8
        }
        'HTML' {
            $bodyHtml = @"
<div style="margin:20px">
<h2>Saude do Sistema</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Status</th><th>Check</th><th>Detalhe</th></tr>
$($health.Checks | ForEach-Object {
    $color = switch ($_.Status) { 'OK' { '#d4edda' } 'AVISO' { '#fff3cd' } 'FALHA' { '#f8d7da' } default { '#e2e3e5' } }
    "<tr style='background-color:$color'><td>$($_.Status)</td><td>$($_.Name)</td><td>$($_.Detail)</td></tr>"
} | Out-String)
</table>

<h2>Restore Points ($($restorePoints.Count))</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>#</th><th>Descricao</th><th>Data</th><th>Tipo</th></tr>
$($restorePoints | ForEach-Object {
    "<tr><td>$($_.SequenceNumber)</td><td>$($_.Description)</td><td>$($_.CreationTime)</td><td>$($_.RestorePointType)</td></tr>"
} | Out-String)
</table>

<h2>Historico de Backups ($($history.Count))</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>Status</th><th>Data</th><th>Caminho</th></tr>
$($history | ForEach-Object {
    $status = if ($_.AllSuccess) { 'OK' } else { 'FALHA' }
    "<tr><td>$status</td><td>$($_.CreatedAt)</td><td>$($_.BackupPath)</td></tr>"
} | Out-String)
</table>
</div>
"@
            $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Relatorio de Backup - WBA Toolkit</title>
<style>body{font-family:Arial,sans-serif;margin:20px}h1{color:#0066cc}table{margin:10px 0}</style>
</head>
<body>
<h1>Relatorio de Backup</h1>
<p>Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Computador: $env:COMPUTERNAME</p>
$bodyHtml
</body>
</html>
"@
            [System.IO.File]::WriteAllText($OutputPath, $html, [System.Text.UTF8Encoding]::new($true))
        }
    }

    Write-Output "Relatorio gerado: $OutputPath"
    $OutputPath
}
