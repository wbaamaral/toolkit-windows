function New-PortalIndexHtml {
    [CmdletBinding()]
    param(
        [string]$ManualReadmePath,
        [string]$TechnicalReferenceUrl = 'referencia/index.html',
        [string]$OperatorUrl = 'operador.html'
    )

    if ($ManualReadmePath -and (Test-Path -LiteralPath $ManualReadmePath)) {
        $raw = [System.IO.File]::ReadAllText($ManualReadmePath, [System.Text.Encoding]::UTF8)
        $readmeHtml = ConvertFrom-MarkdownSimple -Markdown $raw
    }
    else {
        if ($ManualReadmePath) {
            Write-Warning "New-PortalIndexHtml: catálogo não encontrado em '$ManualReadmePath'."
        }
        $readmeHtml = '<p class="muted">Catálogo não disponível.</p>'
    }

    $geradoEm = (Get-Date).ToString('yyyy-MM-dd HH:mm')

    $cards = @'
<div class="card-grid">
  <div class="card">
    <h3>Diagnóstico de Rede</h3>
    <p>Testa conectividade TCP/UDP/ICMP/DNS por alvo. Gera relatório HTML.</p>
    <code>.\diagnostics\networking\Testar-Conectividade-Internet.ps1</code>
  </div>
  <div class="card">
    <h3>Diagnóstico HD100</h3>
    <p>Saúde do disco, processos em alta CPU e gerenciamento de inicialização.</p>
    <code>.\maintenance\Diagnostico-Reparo-HD100.ps1</code>
  </div>
  <div class="card">
    <h3>Inventário</h3>
    <p>Hardware, software instalado, drivers. Exporta HTML, TXT, JSON e PDF.</p>
    <code>.\inventory\Inventario-Hardware-Software.ps1</code>
  </div>
  <div class="card">
    <h3>Limpeza Windows</h3>
    <p>Remove arquivos temporários, cache e logs antigos.</p>
    <code>.\maintenance\limpeza-windows.ps1</code>
  </div>
  <div class="card">
    <h3>Gerenciar Inicialização</h3>
    <p>Lista, habilita e desabilita itens de inicialização do Windows.</p>
    <code>.\maintenance\Gerenciar-Inicializacao-Windows.ps1</code>
  </div>
  <div class="card">
    <h3>Atualização Windows</h3>
    <p>Aplica atualizações do sistema e Chocolatey de forma conservadora.</p>
    <code>.\updates\upgrade-windows.ps1</code>
  </div>
</div>
'@

    $docLinks = @"
<ul>
  <li><a href="$OperatorUrl">Guia rápido do operador</a> — comandos por cenário operacional</li>
  <li><a href="$TechnicalReferenceUrl">Referência técnica</a> — todas as funções e scripts com CBH completo</li>
</ul>
"@

    $body = @"
<p class="muted">Gerado em $geradoEm</p>

<h2>Ferramentas principais</h2>
$cards

<h2>Documentação</h2>
$docLinks

<h2>Catálogo de scripts e módulos</h2>
$readmeHtml
"@

    ConvertTo-StaticDocsHtml -Title 'WBA Windows Toolkit — Portal' -Body $body
}
