function New-DuplicateIpReport {
    <#
    .SYNOPSIS
        Gera tres relatorios (TXT, Markdown, HTML) da analise de IP x MAC.

    .DESCRIPTION
        Recebe a lista de resultados ja agrupada e gera os tres arquivos na pasta
        de destino informada. O HTML usa New-ToolkitHtmlReport (mod. Core) com o
        design system Tailwind local do toolkit (ADR 0012). TXT e Markdown sao
        gerados manualmente, sem cmdlets externos (ConvertTo-Markdown nao existe
        no PowerShell nativo). Todos os arquivos sao gravados em UTF-8 com BOM.

    .PARAMETER Results
        Lista de objetos (IP, MACs, Status) ja consolidada por Detect-DuplicateIp.

    .PARAMETER Context
        Objeto com metadados da varredura (Range, Interface, Timestamp,
        TotalConsultado, TotalEncontrado, TotalDuplicados).

    .PARAMETER OutputPath
        Diretorio onde os tres arquivos serao gravados. Se nao existir, e criado.

    .EXAMPLE
        New-DuplicateIpReport -Results $results -Context $ctx -OutputPath 'C:\Temp\arp'

    .NOTES
        Privada do modulo WbaToolkit.Networking. Requer WbaToolkit.Core carregado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Results,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath
    )

    # Helper: grava texto em UTF-8 com BOM (ADR 0007 — Set-Content -Encoding UTF8
    # sem BOM em PS 5.1; [UTF8Encoding]::new($true) garante o byte-order mark).
    function Write-ReportFile {
        param([string]$Path, [string]$Content)
        $enc = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($Path, $Content, $enc)
    }

    # Cria a pasta de saida se nao existir (idempotencia).
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # --- Consolidacao dos dados de relatorio -----------------------------
    $time       = $Context.Timestamp
    $range      = $Context.Range
    $iface      = if ($Context.Interface) { $Context.Interface } else { '<todas>' }
    $totalRange = $Context.TotalConsultado
    $totalFound = $Context.TotalEncontrado
    $totalDup   = $Context.TotalDuplicados
    $duplicates = @($Results | Where-Object Status -eq 'DUPLICADO')

    # ====================================================================
    # Relatorio 1: TXT (texto plano, monoespacado)
    # ====================================================================
    $txt = New-Object System.Text.StringBuilder
    [void]$txt.AppendLine('==================================================')
    [void]$txt.AppendLine(' RELATORIO DE DUPLICACAO IP x MAC')
    [void]$txt.AppendLine('==================================================')
    [void]$txt.AppendLine("Gerado em       : $time")
    [void]$txt.AppendLine("Faixa consultada: $range")
    [void]$txt.AppendLine("Interface       : $iface")
    [void]$txt.AppendLine("Total na faixa  : $totalRange")
    [void]$txt.AppendLine("IPs com ARP     : $totalFound")
    [void]$txt.AppendLine("IPs duplicados  : $totalDup")
    [void]$txt.AppendLine('--------------------------------------------------')
    [void]$txt.AppendLine('')
    [void]$txt.AppendLine(('{0,-18} {1,-42} {2}' -f [string]'IP', [string]'MAC(s)', [string]'Status'))
    [void]$txt.AppendLine(('-' * 80))
    foreach ($r in $Results) {
        [void]$txt.AppendLine(('{0,-18} {1,-42} {2}' -f [string]$r.IP, [string]$r.MACs, [string]$r.Status))
    }
    [void]$txt.AppendLine('')

    if ($duplicates.Count -gt 0) {
        [void]$txt.AppendLine('==> ATENCAO: IPs com multiplos MACs <==')
        foreach ($d in $duplicates) {
            [void]$txt.AppendLine("  $d.IP")
            foreach ($m in ($d.MACs -split ', ')) {
                [void]$txt.AppendLine("      - $m")
            }
        }
    } else {
        [void]$txt.AppendLine('Nenhuma duplicacao detectada.')
    }
    [void]$txt.AppendLine('')
    [void]$txt.AppendLine('Gerado pelo WBA Windows Toolkit')
    Write-ReportFile -Path (Join-Path $OutputPath 'relatorio.txt') -Content $txt.ToString()

    # ====================================================================
    # Relatorio 2: Markdown (tabela pipes + badges)
    # ====================================================================
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# Relatorio de Duplicacao IP x MAC')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("- **Gerado em:** $time")
    [void]$md.AppendLine('- **Faixa consultada:** ``' + $range + '``')
    [void]$md.AppendLine('- **Interface:** ``' + $iface + '``')
    [void]$md.AppendLine("- **Total na faixa:** $totalRange")
    [void]$md.AppendLine("- **IPs com ARP:** $totalFound")
    [void]$md.AppendLine("- **IPs duplicados:** $totalDup")
    [void]$md.AppendLine('')
    if ($duplicates.Count -gt 0) {
        [void]$md.AppendLine("> :warning: **ATENCAO:** $totalDup IP(s) associados a multiplos MACs.")
        [void]$md.AppendLine('')
    }
    [void]$md.AppendLine('| IP | MAC(s) | Status |')
    [void]$md.AppendLine('|---|---|---|')
    foreach ($r in $Results) {
        $badge = if ($r.Status -eq 'DUPLICADO') { ':warning: DUPLICADO' } else { ':white_check_mark: OK' }
        [void]$md.AppendLine("| $($r.IP) | $($r.MACs) | $badge |")
    }
    [void]$md.AppendLine('')
    if ($duplicates.Count -gt 0) {
        [void]$md.AppendLine('## Duplicados')
        [void]$md.AppendLine('')
        foreach ($d in $duplicates) {
            [void]$md.AppendLine("### $($d.IP)")
            foreach ($m in ($d.MACs -split ', ')) {
                [void]$md.AppendLine("- ``$m``")
            }
            [void]$md.AppendLine('')
        }
    } else {
        [void]$md.AppendLine('_Nenhuma duplicacao detectada._')
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine('---')
    [void]$md.AppendLine('_Gerado pelo WBA Windows Toolkit_')
    Write-ReportFile -Path (Join-Path $OutputPath 'relatorio.md') -Content $md.ToString()

    # ====================================================================
    # Relatorio 3: HTML (via New-ToolkitHtmlReport — ADR 0012)
    # ====================================================================
    # Body montado com as classes do design system do toolkit:
    #   .cards / .card      para o resumo no topo
    #   .section            para a tabela
    #   .badge-green/red    para o status OK/DUPLICADO
    $cardsHtml = @"
<div class="cards">
  <div class="card"><div class="card-icon">&#128202;</div><div class="card-label">Faixa consultada</div><div class="card-value">$range</div></div>
  <div class="card"><div class="card-icon">&#128225;</div><div class="card-label">Hosts com ARP</div><div class="card-value">$totalFound</div><div class="card-sub">de $totalRange na faixa</div></div>
  <div class="card"><div class="card-icon">&#9888;</div><div class="card-label">IPs duplicados</div><div class="card-value" style="color:var(--danger)">$totalDup</div></div>
</div>
"@

    $rowsHtml = New-Object System.Text.StringBuilder
    foreach ($r in $Results) {
        $badgeClass = if ($r.Status -eq 'DUPLICADO') { 'badge-red' } else { 'badge-green' }
        [void]$rowsHtml.AppendLine("      <tr><td class=mono>$($r.IP)</td><td class=mono>$($r.MACs)</td><td><span class=`"badge $badgeClass`">$($r.Status)</span></td></tr>")
    }

    $dupHtml = ''
    if ($duplicates.Count -gt 0) {
        $items = New-Object System.Text.StringBuilder
        foreach ($d in $duplicates) {
            $macList = ($d.MACs -split ', ' | ForEach-Object { "<li class=mono>$_</li>" }) -join "`n        "
            [void]$items.AppendLine("      <li><strong>$($d.IP)</strong><ul>$macList</ul></li>")
        }
        $dupHtml = @"
<div class="section">
  <div class="section-hdr">&#9888; IPs Duplicados ($totalDup)</div>
  <div class="section-body">
    <ul>
$items    </ul>
  </div>
</div>
"@
    }

    $tableHtml = @"
<div class="section">
  <div class="section-hdr">&#128202; Detalhamento IP x MAC</div>
  <div class="section-body">
    <table class="data-table">
      <thead><tr><th>IP</th><th>MAC(s)</th><th>Status</th></tr></thead>
      <tbody>
$($rowsHtml.ToString())      </tbody>
    </table>
  </div>
</div>
"@

    $bodyHtml = $cardsHtml + "`n" + $dupHtml + "`n" + $tableHtml

    $meta = @(
        "Faixa: $range",
        "Interface: $iface",
        "Gerado em: $time"
    )

    $html = New-ToolkitHtmlReport `
        -Title 'Relatorio de Duplicacao IP x MAC' `
        -Subtitle "Hosts com ARP: $totalFound de $totalRange | Duplicados: $totalDup" `
        -Icon '&#128225;' `
        -MetaRight $meta `
        -Body $bodyHtml `
        -ShowPrintButton

    Write-ReportFile -Path (Join-Path $OutputPath 'relatorio.html') -Content $html

    return (Join-Path $OutputPath 'relatorio.txt'), (Join-Path $OutputPath 'relatorio.md'), (Join-Path $OutputPath 'relatorio.html')
}
