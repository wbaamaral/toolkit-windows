#Requires -Version 5.1
<#
.SYNOPSIS
    Gera relatório HTML com as propostas de normalização do Dropbox.

.DESCRIPTION
    Constrói cards de resumo e tabela detalhada com as propostas de correção
    por arquivo (de → para), delegando o esqueleto HTML para
    New-ToolkitHtmlReport. Inclui filtro de busca JavaScript para facilitar
    navegação.

    Quando -Diretorios é informado, inclui também um editor interativo por
    diretório: checkbox de seleção, campo de texto editável para o nome
    proposto (nível mais profundo da cadeia de encurtamento), recálculo ao
    vivo do comprimento do caminho resultante (JS puro, sem dependência
    nova) e um botão "Baixar JSON corrigido" (Blob + <a download>) que gera
    um arquivo pronto para reinjeção em -Modo Aplicar -PropostaFile.

.PARAMETER DropboxPath
    Caminho raiz do Dropbox analisado.

.PARAMETER TotalPropostas
    Total de propostas geradas.

.PARAMETER Selecionadas
    Número de propostas selecionadas para aplicação.

.PARAMETER Propostas
    Lista de propostas por arquivo (objetos com id, selecionado,
    caminho_original, caminho_proposto, tipo_correcao, motivo).

.PARAMETER Diretorios
    Lista de diretórios problemáticos (objetos com id, diretorio,
    nome_original, nome_proposto, caminho_original, caminho_proposto,
    total_arquivos, maior_sufixo, problema_pred, selecionado, cadeia).
    Quando informada, habilita o editor interativo. Opcional -- omitido,
    o relatório mantém apenas a tabela de propostas por arquivo (
    compatibilidade com chamadas anteriores a esta funcionalidade).

.PARAMETER MetadataOriginal
    Objeto de metadata original do JSON de proposta, repassado sem
    alteração no JSON corrigido gerado pelo editor (mantém
    diagnostico_origem e demais campos consistentes para -Modo Aplicar).

.PARAMETER LimiteCaminho
    Comprimento máximo de caminho considerado pelo editor ao colorir o
    comprimento resultante (verde/vermelho). Padrão: 260.

.EXAMPLE
    $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
        -TotalPropostas 100 -Selecionadas 80 -Propostas $propostas

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
  <div class="card"><div class="card-label">Total Propostas</div><div class="card-value">$TotalPropostas</div></div>
  <div class="card"><div class="card-label">Selecionadas</div><div class="card-value badge-green">$Selecionadas</div></div>
  <div class="card"><div class="card-label">Não Selecionadas</div><div class="card-value badge-red">$naoSelecionadas</div></div>
</div>
"@

    # Tabela de propostas por arquivo
    $rows = foreach ($p in $Propostas) {
        $status = if ($p.selecionado) {
            '<span class="badge badge-green">✓</span>'
        } else {
            '<span class="badge badge-red">✗</span>'
        }
        $de = [System.Net.WebUtility]::HtmlEncode($p.caminho_original)
        $para = [System.Net.WebUtility]::HtmlEncode($p.caminho_proposto)
        $tipo = [System.Net.WebUtility]::HtmlEncode($p.tipo_correcao)
        $motivo = [System.Net.WebUtility]::HtmlEncode($p.motivo)
        "<tr><td>$($p.id)</td><td>$status</td><td class='mono'>$de</td><td class='mono'>$para</td><td>$tipo</td><td>$motivo</td></tr>"
    }

    $table = @"
<div class="section">
  <div class="section-hdr">Propostas de Correção (por arquivo)</div>
  <div class="section-body">
    <input type="text" id="search" onkeyup="filterTable()" placeholder="Pesquisar caminhos..." style="width:100%;padding:8px;margin-bottom:10px;border:1px solid #e2e8f0;border-radius:4px;">
    <table class="data-table" id="propostasTable">
      <thead><tr><th>ID</th><th>Status</th><th>De</th><th>Para</th><th>Tipo</th><th>Motivo</th></tr></thead>
      <tbody>
        $($rows -join "`n")
      </tbody>
    </table>
  </div>
</div>
<script>
function filterTable() {
  var input = document.getElementById('search');
  var filter = input.value.toUpperCase();
  var table = document.getElementById('propostasTable');
  var tr = table.getElementsByTagName('tr');
  for (var i = 1; i < tr.length; i++) {
    var td = tr[i].getElementsByTagName('td')[2];
    if (td) {
      var txtValue = td.textContent || td.innerText;
      tr[i].style.display = txtValue.toUpperCase().indexOf(filter) > -1 ? '' : 'none';
    }
  }
}
</script>
"@

    # Editor interativo de diretorios (opcional -- so quando -Diretorios e informado)
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
            $nomeEnc = [System.Net.WebUtility]::HtmlEncode([string]$d.nome_proposto)
            $problemaEnc = [System.Net.WebUtility]::HtmlEncode([string]$d.problema_pred)
            $cadeiaTxt = if (@($d.cadeia).Count -gt 1) { " (cadeia: $(@($d.cadeia).Count) niveis)" } else { '' }
            $checkedAttr = if ($d.selecionado) { 'checked' } else { '' }
            @"
<tr data-idx="$i">
  <td><input type="checkbox" onchange="toggleSelecionado($i, this.checked)" $checkedAttr></td>
  <td>$($d.id)</td>
  <td class="mono">$dirEnc</td>
  <td><input type="text" class="edit-nome" value="$nomeEnc" oninput="atualizarNome($i, this.value)" style="width:100%;padding:4px;border:1px solid #e2e8f0;border-radius:4px;"></td>
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
    <div class="alert">Limite de caminho considerado: $LimiteCaminho caracteres. O comprimento mostrado usa o arquivo mais longo dentro do diretório.</div>
    <table class="data-table" id="diretoriosTable">
      <thead><tr><th>Sel.</th><th>ID</th><th>Diretório</th><th>Nome proposto</th><th>Comprimento</th><th>Itens</th><th>Problema</th></tr></thead>
      <tbody>
        $($linhasHtml -join "`n")
      </tbody>
    </table>
    <div style="margin-top:12px;text-align:right"><button onclick="baixarJsonCorrigido()">Baixar JSON corrigido</button></div>
  </div>
</div>
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

    $body = "$cards`n$table`n$editorSection"

    return New-ToolkitHtmlReport `
        -Title 'Propostas de Normalização Dropbox' `
        -Subtitle $DropboxPath `
        -Icon '&#128260;' `
        -MetaRight @("Total: $TotalPropostas", "Selecionadas: $Selecionadas") `
        -Body $body `
        -ShowPrintButton
}
