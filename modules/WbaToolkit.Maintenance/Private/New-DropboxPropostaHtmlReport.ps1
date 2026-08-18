#Requires -Version 5.1
<#
.SYNOPSIS
    Gera relatório HTML com as propostas de normalização do Dropbox.

.DESCRIPTION
    Constrói cards de resumo e um editor interativo por diretório
    (checkbox de seleção, comparação De/Para do caminho empilhada com
    truncamento inteligente para caminhos longos, campo de texto editável
    para o nome proposto, recálculo ao vivo do comprimento do caminho
    resultante) sobre o esqueleto HTML de New-ToolkitHtmlReport. Inclui um
    botão "Baixar JSON corrigido" (Blob + <a download>) que gera um
    arquivo pronto para reinjeção em -Modo Aplicar -PropostaFile.

    A unidade de correção real é o diretório (a renomeação acontece na
    pasta, nunca no arquivo em si), por isso o relatório não lista os
    arquivos individualmente -- eles só aparecem como contagem por
    diretório.

.PARAMETER DropboxPath
    Caminho raiz do Dropbox analisado.

.PARAMETER TotalPropostas
    Total de arquivos problemáticos cobertos pela proposta (soma de
    arquivos em todos os diretórios selecionados).

.PARAMETER Selecionadas
    Número desses arquivos cujo diretório está selecionado para aplicação.

.PARAMETER Propostas
    Lista de propostas por arquivo (id, caminho_original, etc.) --
    preservada apenas para ser embutida no JSON baixável pelo editor
    (compatibilidade com o esquema consumido por -Modo Aplicar). Não é
    exibida como tabela.

.PARAMETER Diretorios
    Lista de diretórios problemáticos (objetos com id, diretorio,
    nome_original, nome_proposto, caminho_original, caminho_proposto,
    total_arquivos, maior_sufixo, problema_pred, selecionado, cadeia).
    Quando informada, habilita o editor interativo (visão principal do
    relatório).

.PARAMETER MetadataOriginal
    Objeto de metadata original do JSON de proposta, repassado sem
    alteração no JSON corrigido gerado pelo editor (mantém
    diagnostico_origem e demais campos consistentes para -Modo Aplicar).

.PARAMETER LimiteCaminho
    Comprimento máximo de caminho considerado pelo editor ao colorir o
    comprimento resultante (verde/vermelho). Padrão: 260.

.EXAMPLE
    $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
        -TotalPropostas 100 -Selecionadas 80 -Propostas $propostas `
        -Diretorios $diretorios -MetadataOriginal $metadata -LimiteCaminho 260

.OUTPUTS
    System.String
    HTML completo pronto para gravação em arquivo.
#>
function New-DropboxPropostaHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DropboxPath,

        [Parameter(Mandatory = $true)]
        [int]$TotalPropostas,

        [Parameter(Mandatory = $true)]
        [int]$Selecionadas,

        [Parameter(Mandatory = $true)]
        [object[]]$Propostas,

        [Parameter(Mandatory = $false)]
        [object[]]$Diretorios = @(),

        [Parameter(Mandatory = $false)]
        [object]$MetadataOriginal = $null,

        [Parameter(Mandatory = $false)]
        [int]$LimiteCaminho = 260
    )

    $naoSelecionadas = $TotalPropostas - $Selecionadas

    # Cards de resumo
    $cards = @"
<div class="cards">
  <div class="card"><div class="card-label">Total Arquivos</div><div class="card-value">$TotalPropostas</div></div>
  <div class="card"><div class="card-label">Selecionados</div><div class="card-value badge-green">$Selecionadas</div></div>
  <div class="card"><div class="card-label">Não Selecionados</div><div class="card-value badge-red">$naoSelecionadas</div></div>
</div>
"@

    # Editor interativo de diretorios -- visao principal do relatorio (a
    # correcao acontece no diretorio, nao no arquivo, entao nao ha tabela
    # por arquivo).
    $editorSection = ''
    if ($Diretorios -and @($Diretorios).Count -gt 0) {
        $linhasEditor = foreach ($d in @($Diretorios)) {
            $cadeiaEfetiva = if ($d.PSObject.Properties['cadeia'] -and @($d.cadeia).Count -gt 0) {
                @($d.cadeia)
            }
            else {
                @([pscustomobject]@{ nivel = 1; caminho_original = $d.diretorio; nome_proposto = $d.nome_proposto })
            }
            $prefixoAncestral = Split-Path -Parent ([string]$d.caminho_proposto)
            $maiorSufixo = if ($d.PSObject.Properties['maior_sufixo']) { [int]$d.maior_sufixo } else { 0 }
            $editadoManual = if ($d.PSObject.Properties['editado_manualmente']) { [bool]$d.editado_manualmente } else { $false }

            [pscustomobject]@{
                id                    = $d.id
                diretorio             = $d.diretorio
                nome_original         = $d.nome_original
                nome_proposto         = $d.nome_proposto
                nome_proposto_inicial = $d.nome_proposto
                caminho_original      = $d.caminho_original
                caminho_proposto      = $d.caminho_proposto
                prefixo_ancestral     = $prefixoAncestral
                total_arquivos        = $d.total_arquivos
                maior_sufixo          = $maiorSufixo
                problema_pred         = $d.problema_pred
                selecionado           = [bool]$d.selecionado
                editado_manualmente   = $editadoManual
                cadeia                = $cadeiaEfetiva
            }
        }
        $linhasEditor = @($linhasEditor)

        $diretoriosJsonSafe = (($linhasEditor | ConvertTo-Json -Depth 8 -Compress)) -replace '</', '<\/'
        $metadataJsonSafe = $(if ($MetadataOriginal) { ($MetadataOriginal | ConvertTo-Json -Depth 8 -Compress) } else { '{}' }) -replace '</', '<\/'
        $propostasJsonSafe = ((@($Propostas) | ConvertTo-Json -Depth 8 -Compress)) -replace '</', '<\/'

        $linhasHtml = for ($i = 0; $i -lt $linhasEditor.Count; $i++) {
            $d = $linhasEditor[$i]
            $dirEnc = [System.Net.WebUtility]::HtmlEncode([string]$d.diretorio)
            $prefixoEnc = [System.Net.WebUtility]::HtmlEncode([string]$d.prefixo_ancestral)
            $nomeEnc = [System.Net.WebUtility]::HtmlEncode([string]$d.nome_proposto)
            $problemaEnc = [System.Net.WebUtility]::HtmlEncode([string]$d.problema_pred)
            $cadeiaTxt = if (@($d.cadeia).Count -gt 1) { " (cadeia: $(@($d.cadeia).Count) niveis)" } else { '' }
            $checkedAttr = if ($d.selecionado) { 'checked' } else { '' }
            @"
<tr data-idx="$i">
  <td><input type="checkbox" onchange="toggleSelecionado($i, this.checked)" $checkedAttr></td>
  <td>$($d.id)</td>
  <td class="depara">
    <div class="depara-linha" title="$dirEnc">
      <span class="depara-rotulo depara-rotulo-de">De</span>
      <span class="depara-texto depara-trunc">$dirEnc</span>
    </div>
    <div class="depara-linha" title="$prefixoEnc\$nomeEnc">
      <span class="depara-rotulo depara-rotulo-para">Para</span>
      <span class="depara-texto depara-trunc depara-prefixo">$prefixoEnc\</span>
      <input type="text" class="edit-nome" value="$nomeEnc" oninput="atualizarNome($i, this.value)">
    </div>
  </td>
  <td><span id="len-$i" class="badge"></span></td>
  <td>$($d.total_arquivos)</td>
  <td>$problemaEnc$cadeiaTxt</td>
</tr>
"@
        }

        $editorSection = @"
<div class="section">
  <div class="section-hdr">Editor de Diretórios (edite o nome, selecione e baixe o JSON corrigido)</div>
  <div class="section-body">
    <div class="alert">Limite de caminho considerado: $LimiteCaminho caracteres. O comprimento mostrado usa o arquivo mais longo dentro do diretório. Passe o mouse sobre um caminho truncado para ver o valor completo.</div>
    <input type="text" id="search" onkeyup="filterDiretorios()" placeholder="Pesquisar diretorios..." style="width:100%;padding:8px;margin-bottom:10px;border:1px solid var(--border);border-radius:4px;">
    <div class="depara-scroll">
      <table class="data-table depara-table" id="diretoriosTable">
        <thead><tr><th>Sel.</th><th>ID</th><th>De / Para</th><th>Comprimento</th><th>Itens</th><th>Problema</th></tr></thead>
        <tbody>
          $($linhasHtml -join "`n")
        </tbody>
      </table>
    </div>
    <div style="margin-top:12px;text-align:right"><button onclick="baixarJsonCorrigido()">Baixar JSON corrigido</button></div>
  </div>
</div>
<style>
.depara-scroll{max-height:70vh;overflow-y:auto;border:1px solid var(--border);border-radius:var(--radius)}
.depara-table thead th{position:sticky;top:0;z-index:1;background:#f8fafc}
.depara-table tbody tr:nth-child(even){background:#f8fafc}
.depara-table tbody tr:nth-child(even):hover td{background:#f1f5f9}
td.depara{min-width:360px}
.depara-linha{display:flex;align-items:center;gap:.4rem;padding:.1rem 0;font-family:var(--font-mono);font-size:.8rem;white-space:nowrap}
.depara-rotulo{flex:0 0 auto;font-family:var(--font-sans);font-size:.65rem;font-weight:700;text-transform:uppercase;letter-spacing:.04em;border-radius:4px;padding:.05rem .4rem}
.depara-rotulo-de{color:var(--danger);background:#fef2f2}
.depara-rotulo-para{color:var(--success);background:#f0fdf4}
.depara-texto{overflow:hidden;text-overflow:ellipsis;direction:rtl;text-align:left;unicode-bidi:plaintext}
.depara-prefixo{flex:0 1 auto;color:var(--muted)}
.depara-linha .depara-texto:not(.depara-prefixo){flex:1 1 auto}
.edit-nome{flex:0 1 220px;min-width:120px;padding:3px 6px;border:1px solid var(--border);border-radius:4px;font-family:var(--font-mono);font-size:.8rem;font-weight:600}
</style>
<script>
function filterDiretorios() {
  var filter = document.getElementById('search').value.toUpperCase();
  var tr = document.querySelectorAll('#diretoriosTable tbody tr');
  tr.forEach(function (row) {
    var texto = row.textContent || row.innerText;
    row.style.display = texto.toUpperCase().indexOf(filter) > -1 ? '' : 'none';
  });
}
</script>
"@
        $editorSection += @"
<script>
var LIMITE_CAMINHO = $LimiteCaminho;
var diretoriosData = $diretoriosJsonSafe;
var metadataOriginal = $metadataJsonSafe;
var propostasOriginal = $propostasJsonSafe;

function calcularComprimento(idx) {
  var row = diretoriosData[idx];
  var len = (row.prefixo_ancestral ? row.prefixo_ancestral.length : 0) + 1 + row.nome_proposto.length + (row.maior_sufixo || 0);
  var span = document.getElementById('len-' + idx);
  if (span) {
    span.textContent = len + ' / ' + LIMITE_CAMINHO;
    span.className = 'badge ' + (len <= LIMITE_CAMINHO ? 'badge-green' : 'badge-red');
  }
  return len;
}

function atualizarNome(idx, valor) {
  var row = diretoriosData[idx];
  row.nome_proposto = valor;
  row.editado_manualmente = (valor !== row.nome_proposto_inicial);
  if (row.cadeia && row.cadeia.length > 0) {
    row.cadeia[row.cadeia.length - 1].nome_proposto = valor;
  }
  calcularComprimento(idx);
}

function toggleSelecionado(idx, valor) {
  diretoriosData[idx].selecionado = valor;
}

function baixarJsonCorrigido() {
  var payload = {
    metadata: metadataOriginal,
    diretorios: diretoriosData,
    propostas: propostasOriginal
  };
  var blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  var url = URL.createObjectURL(blob);
  var a = document.createElement('a');
  a.href = url;
  a.download = 'correcoes-propostas-corrigido.json';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

for (var i = 0; i < diretoriosData.length; i++) { calcularComprimento(i); }
</script>
"@
    }

    $body = "$cards`n$editorSection"

    return New-ToolkitHtmlReport `
        -Title 'Propostas de Normalização Dropbox' `
        -Subtitle $DropboxPath `
        -Icon '&#128260;' `
        -MetaRight @("Total: $TotalPropostas", "Selecionados: $Selecionadas") `
        -Body $body `
        -ShowPrintButton
}
