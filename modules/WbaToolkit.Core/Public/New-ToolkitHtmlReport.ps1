function New-ToolkitHtmlReport {
    <#
    .SYNOPSIS
        Gera esqueleto HTML padronizado para relatorios do toolkit.

    .DESCRIPTION
        Retorna uma string HTML completa com CSS, header, footer e container pronto
        para receber o conteudo especifico do relatorio.

        O CSS inclui: @font-face (Inter + JetBrains Mono), variaveis CSS, classes
        componentes (cards, sections, tables, badges, barras) e print CSS.

    .PARAMETER Title
        Titulo do relatorio exibido no header.

    .PARAMETER Subtitle
        Subtitulo exibido abaixo do titulo no header.

    .PARAMETER Icon
        Emoji/HTML entity exibido antes do titulo (default: &#128196;).

    .PARAMETER MetaRight
        Linhas de metadados exibidas no lado direito do header (array de strings).

    .PARAMETER Body
        Conteudo HTML especifico do relatorio (va entre <main> e </main>).

    .PARAMETER FooterText
        Texto do footer (default: "Gerado pelo WBA Windows Toolkit").

    .PARAMETER ShowPrintButton
        Se $true, exibe botao de impressao acima do header.

    .EXAMPLE
        $html = New-ToolkitHtmlReport -Title "Relatorio de Disco" -SubTitle "PVH-RESERVA00" -Body $bodyHtml

    .EXAMPLE
        $html = New-ToolkitHtmlReport -Title "Backup Drivers" -Icon "&#128187;" -MetaRight @("Modo: Backup","Data: 22/07/2026") -Body $content
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$Subtitle = '',

        [Parameter(Mandatory = $false)]
        [string]$Icon = '&#128196;',

        [Parameter(Mandatory = $false)]
        [string[]]$MetaRight = @(),

        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $false)]
        [string]$FooterText = 'Gerado pelo WBA Windows Toolkit',

        [Parameter(Mandatory = $false)]
        [switch]$ShowPrintButton
    )

    # Montar meta-right
    $metaHtml = ($MetaRight | ForEach-Object { "    <div>$_</div>" }) -join "`n"

    # Botao de impressao (opcional)
    $toolbarHtml = ''
    if ($ShowPrintButton) {
        $toolbarHtml = '    <div class="toolbar"><button onclick="window.print()">Imprimir Relatorio</button></div>'
    }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$Title</title>
<style>
@font-face{font-family:'Inter';font-style:normal;font-weight:400;font-display:swap;src:local('Inter Regular'),local('Segoe UI'),local('sans-serif')}
@font-face{font-family:'Inter';font-style:normal;font-weight:700;font-display:swap;src:local('Inter Bold'),local('Segoe UI Bold'),local('sans-serif')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:400;font-display:swap;src:local('JetBrains Mono Regular'),local('Consolas'),local('monospace')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:700;font-display:swap;src:local('JetBrains Mono Bold'),local('Consolas Bold'),local('monospace')}
:root{--primary:#1e3a5f;--primary-lt:#2d5986;--accent:#2563eb;--success:#16a34a;--warning:#d97706;--danger:#dc2626;--bg:#f0f4f8;--surface:#fff;--border:#e2e8f0;--text:#1e293b;--muted:#64748b;--radius:8px;--font-sans:'Inter','Segoe UI',system-ui,-apple-system,sans-serif;--font-mono:'JetBrains Mono','Consolas',ui-monospace,monospace}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{font-family:var(--font-sans);background:var(--bg);color:var(--text);font-size:14px;line-height:1.5}
header{background:linear-gradient(135deg,var(--primary) 0%,var(--primary-lt) 100%);color:#fff;padding:2rem 2.5rem;display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:1rem}
header .title-block h1{font-size:1.6rem;font-weight:700;letter-spacing:-0.02em}
header .title-block p{opacity:.75;font-size:.85rem;margin-top:.25rem}
header .meta-block{text-align:right;font-size:.8rem;opacity:.8;line-height:1.8}
main{max-width:1100px;margin:1.5rem auto;padding:0 1.5rem}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:1rem;margin-bottom:1.5rem}
.card{background:var(--surface);border-radius:var(--radius);padding:1.1rem 1.25rem;box-shadow:0 1px 6px rgba(0,0,0,.07);border-left:4px solid var(--accent);transition:box-shadow .15s}
.card:hover{box-shadow:0 4px 14px rgba(0,0,0,.12)}
.card-icon{font-size:1.4rem;margin-bottom:.4rem}
.card-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:600}
.card-value{font-size:1.05rem;font-weight:700;color:var(--primary);margin-top:.2rem}
.card-sub{font-size:.75rem;color:var(--muted);margin-top:.15rem}
.section{background:var(--surface);border-radius:var(--radius);box-shadow:0 1px 6px rgba(0,0,0,.07);margin-bottom:1.25rem;overflow:hidden}
.section-hdr{background:var(--primary);color:#fff;padding:.75rem 1.5rem;font-size:.9rem;font-weight:700;display:flex;align-items:center;gap:.5rem}
.section-body{padding:1.25rem 1.5rem}
h2{font-size:1rem;font-weight:700;color:var(--text);margin:1.5rem 0 .75rem;padding-bottom:.5rem;border-bottom:1px solid var(--border)}
.data-table{width:100%;border-collapse:collapse;font-size:.82rem}
.data-table thead th{background:#f8fafc;color:var(--primary);font-weight:700;padding:.55rem 1rem;text-align:left;border-bottom:2px solid var(--border);white-space:nowrap}
.data-table tbody td{padding:.5rem 1rem;border-bottom:1px solid #f1f5f9}
.data-table tbody tr:last-child td{border-bottom:none}
.data-table tbody tr:hover td{background:#f8faff}
.kv-table{width:100%;border-collapse:collapse}
.kv-table th{width:220px;font-weight:600;font-size:.8rem;color:var(--muted);text-align:left;padding:.4rem .75rem .4rem 0;border-bottom:1px solid var(--border);vertical-align:top}
.kv-table td{font-size:.85rem;padding:.4rem 0;border-bottom:1px solid var(--border)}
.kv-table tr:last-child th,.kv-table tr:last-child td{border-bottom:none}
.badge{display:inline-block;padding:.15em .55em;border-radius:4px;font-size:.72rem;font-weight:700;white-space:nowrap}
.badge-green{background:#dcfce7;color:#15803d}
.badge-yellow{background:#fef9c3;color:#92400e}
.badge-red{background:#fee2e2;color:#991b1b}
.badge-blue{background:#dbeafe;color:#1e40af}
.badge-gray{background:#f1f5f9;color:#475569}
.disk-bar{background:#e2e8f0;border-radius:4px;height:10px;overflow:hidden}
.disk-fill{height:100%;border-radius:4px;transition:width .3s}
.bar-ok{background:var(--success)}
.bar-warn{background:var(--warning)}
.bar-danger{background:var(--danger)}
.alert{background:#fffbeb;border:1px solid #fcd34d;padding:12px 16px;border-radius:6px;margin:12px 0}
.info-box{background:#f9fafb;border:1px solid var(--border);border-radius:8px;padding:16px}
.muted{color:var(--muted)}
.small{font-size:11px}
.mono{font-family:var(--font-mono);font-size:.8rem;word-break:break-all}
.nowrap{white-space:nowrap}
.meta{background:#f0f4f8;padding:12px 16px;border-radius:4px;margin-bottom:16px;font-size:12px}
.link-btn{display:inline-block;padding:.4rem .75rem;background:var(--accent);color:#fff;font-size:.75rem;font-weight:600;border-radius:4px;text-decoration:none;transition:background .15s}
.link-btn:hover{background:#1d4ed8}
.toolbar{max-width:1100px;margin:0 auto;padding:0 1.5rem;text-align:right}
button{border:0;border-radius:4px;background:var(--accent);color:#fff;cursor:pointer;font:inherit;padding:8px 14px;transition:background .15s}
button:hover{background:#1d4ed8}
footer{text-align:center;color:var(--muted);font-size:.78rem;padding:1.5rem;margin-top:.5rem}
@page{size:A4;margin:15mm}
@media print{body{background:#fff;font-size:11px}header,.section-hdr{print-color-adjust:exact;-webkit-print-color-adjust:exact}.toolbar{display:none}*{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style>
</head>
<body>
$toolbarHtml
<header>
  <div class="title-block">
    <h1>$Icon $Title</h1>
    <p>$Subtitle</p>
  </div>
  <div class="meta-block">
$metaHtml
  </div>
</header>
<main>
$Body
</main>
<footer>$FooterText</footer>
</body>
</html>
"@

    return $html
}
