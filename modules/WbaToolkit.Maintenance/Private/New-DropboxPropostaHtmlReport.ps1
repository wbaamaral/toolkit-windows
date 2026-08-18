#Requires -Version 5.1
<#
.SYNOPSIS
    Gera relatório HTML com as propostas de normalização do Dropbox.

.DESCRIPTION
    Constrói cards de resumo e tabela detalhada com as propostas de correção
    (de → para), delegando o esqueleto HTML para New-ToolkitHtmlReport.
    Inclui filtro de busca JavaScript para facilitar navegação.

.PARAMETER DropboxPath
    Caminho raiz do Dropbox analisado.

.PARAMETER TotalPropostas
    Total de propostas geradas.

.PARAMETER Selecionadas
    Número de propostas selecionadas para aplicação.

.PARAMETER Propostas
    Lista de propostas (objetos com id, selecionado, caminho_original,
    caminho_proposto, tipo_correcao, motivo).

.EXAMPLE
    $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
        -TotalPropostas 100 -Selecionadas 80 -Propostas $propostas

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
        [object[]]$Propostas
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

    # Tabela de propostas
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
  <div class="section-hdr">Propostas de Correção</div>
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

    $body = "$cards`n$table"

    return New-ToolkitHtmlReport `
        -Title 'Propostas de Normalização Dropbox' `
        -Subtitle $DropboxPath `
        -Icon '&#128260;' `
        -MetaRight @("Total: $TotalPropostas", "Selecionadas: $Selecionadas") `
        -Body $body `
        -ShowPrintButton
}
