#Requires -Version 5.1
<#
.SYNOPSIS
    Gera relatório HTML com o resultado da aplicação das correções do Dropbox.

.DESCRIPTION
    Constrói cards de resumo e tabela detalhada com o resultado de cada
    correção aplicada (de → para, status, backup, erros), delegando o
    esqueleto HTML para New-ToolkitHtmlReport.
    Inclui filtro de busca JavaScript para facilitar navegação.

.PARAMETER DropboxPath
    Caminho raiz do Dropbox analisado.

.PARAMETER TotalAplicadas
    Total de correções aplicadas.

.PARAMETER Sucesso
    Número de correções bem-sucedidas.

.PARAMETER Falha
    Número de correções que falharam.

.PARAMETER Resultados
    Lista de resultados (objetos com id, de, para, status, backup, erro, timestamp).

.EXAMPLE
    $html = New-DropboxResultadoHtmlReport -DropboxPath 'C:\Dropbox' `
        -TotalAplicadas 80 -Sucesso 78 -Falha 2 -Resultados $resultados

.OUTPUTS
    System.String
    HTML completo pronto para gravação em arquivo.
#>
function New-DropboxResultadoHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DropboxPath,

        [Parameter(Mandatory = $true)]
        [int]$TotalAplicadas,

        [Parameter(Mandatory = $true)]
        [int]$Sucesso,

        [Parameter(Mandatory = $true)]
        [int]$Falha,

        [Parameter(Mandatory = $true)]
        [object[]]$Resultados
    )

    # Cards de resumo
    $cards = @"
<div class="cards">
  <div class="card"><div class="card-label">Total Aplicadas</div><div class="card-value">$TotalAplicadas</div></div>
  <div class="card"><div class="card-label">Sucesso</div><div class="card-value badge-green">$Sucesso</div></div>
  <div class="card"><div class="card-label">Falha</div><div class="card-value badge-red">$Falha</div></div>
</div>
"@

    # Tabela de resultados
    $rows = foreach ($r in $Resultados) {
        $status = if ($r.status -eq 'Sucesso') {
            '<span class="badge badge-green">✓ Sucesso</span>'
        } else {
            '<span class="badge badge-red">✗ Erro</span>'
        }
        $de = [System.Net.WebUtility]::HtmlEncode($r.de)
        $para = [System.Net.WebUtility]::HtmlEncode($r.para)
        $backup = if ($r.backup) { [System.Net.WebUtility]::HtmlEncode($r.backup) } else { '-' }
        $erro = if ($r.erro) { [System.Net.WebUtility]::HtmlEncode($r.erro) } else { '' }
        $timestamp = if ($r.timestamp) { [System.Net.WebUtility]::HtmlEncode($r.timestamp) } else { '' }
        "<tr><td>$($r.id)</td><td>$status</td><td class='mono'>$de</td><td class='mono'>$para</td><td class='mono small'>$backup</td><td>$erro</td><td class='small'>$timestamp</td></tr>"
    }

    $table = @"
<div class="section">
  <div class="section-hdr">Resultado da Aplicação</div>
  <div class="section-body">
    <input type="text" id="search" onkeyup="filterTable()" placeholder="Pesquisar caminhos..." style="width:100%;padding:8px;margin-bottom:10px;border:1px solid #e2e8f0;border-radius:4px;">
    <table class="data-table" id="resultadosTable">
      <thead><tr><th>ID</th><th>Status</th><th>De</th><th>Para</th><th>Backup</th><th>Erro</th><th>Timestamp</th></tr></thead>
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
  var table = document.getElementById('resultadosTable');
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
        -Title 'Resultado da Normalização Dropbox' `
        -Subtitle $DropboxPath `
        -Icon '&#128260;' `
        -MetaRight @("Total: $TotalAplicadas", "Sucesso: $Sucesso", "Falha: $Falha") `
        -Body $body `
        -ShowPrintButton
}
