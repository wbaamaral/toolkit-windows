#Requires -Version 5.1
<#
.SYNOPSIS
    Gera relatório HTML com o resultado da aplicação das correções do Dropbox.

.DESCRIPTION
    Constrói cards de resumo e tabela detalhada com o resultado de cada
    correção aplicada (de → para, status, erros), delegando o esqueleto
    HTML para New-ToolkitHtmlReport. Inclui filtro de busca JavaScript para
    facilitar navegação.

    Quando um resultado tem cadeia de encadeamento com mais de um nível
    (propriedade 'cadeia'), os níveis intermediários (raso -> profundo) são
    listados abaixo da linha principal para auditoria.

.PARAMETER DropboxPath
    Caminho raiz do Dropbox analisado.

.PARAMETER TotalAplicadas
    Total de correções aplicadas.

.PARAMETER Sucesso
    Número de correções bem-sucedidas.

.PARAMETER Falha
    Número de correções que falharam.

.PARAMETER Resultados
    Lista de resultados (objetos com id, diretorio_origem,
    diretorio_destino, nome_original, nome_novo, status, erro, timestamp e,
    opcionalmente, cadeia).

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

    # Aceita tanto o esquema atual (diretorio_origem/diretorio_destino/nome_novo)
    # quanto um esquema legado (de/para/backup), para compatibilidade com
    # JSON de resultado gerado por versoes anteriores do script.
    $rows = foreach ($r in $Resultados) {
        $status = if ($r.status -eq 'Sucesso') {
            '<span class="badge badge-green">✓ Sucesso</span>'
        } else {
            '<span class="badge badge-red">✗ Erro</span>'
        }

        $origemVal = if ($r.PSObject.Properties['diretorio_origem']) { $r.diretorio_origem } else { $r.de }
        $destinoVal = if ($r.PSObject.Properties['diretorio_destino']) { $r.diretorio_destino } else { $r.para }

        $de = [System.Net.WebUtility]::HtmlEncode([string]$origemVal)
        $para = [System.Net.WebUtility]::HtmlEncode([string]$destinoVal)
        $erro = if ($r.erro) { [System.Net.WebUtility]::HtmlEncode([string]$r.erro) } else { '' }
        $timestamp = if ($r.timestamp) { [System.Net.WebUtility]::HtmlEncode([string]$r.timestamp) } else { '' }

        $cadeiaHtml = ''
        if ($r.PSObject.Properties['cadeia'] -and @($r.cadeia).Count -gt 1) {
            $niveis = foreach ($nivelItem in (@($r.cadeia) | Sort-Object nivel)) {
                $nivelStatus = if ($nivelItem.status -eq 'Sucesso') { 'badge-green' } elseif ($nivelItem.status -eq 'NaoExecutado') { 'badge-gray' } else { 'badge-red' }
                $origemNivel = [System.Net.WebUtility]::HtmlEncode([string]$nivelItem.caminho_original)
                $nomeNivel = [System.Net.WebUtility]::HtmlEncode([string]$nivelItem.nome_proposto)
                "<div><span class='badge $nivelStatus'>Nível $($nivelItem.nivel)</span> <span class='mono small'>$origemNivel</span> -&gt; $nomeNivel</div>"
            }
            $cadeiaHtml = "<td colspan='7'>$($niveis -join "`n")</td>"
        }

        $linhaPrincipal = "<tr><td>$($r.id)</td><td>$status</td><td class='mono'>$de</td><td class='mono'>$para</td><td>$erro</td><td class='small'>$timestamp</td></tr>"
        if ($cadeiaHtml) {
            "$linhaPrincipal`n<tr class='cadeia-detalhe'>$cadeiaHtml</tr>"
        }
        else {
            $linhaPrincipal
        }
    }

    $table = @"
<div class="section">
  <div class="section-hdr">Resultado da Aplicação</div>
  <div class="section-body">
    <input type="text" id="search" onkeyup="filterTable()" placeholder="Pesquisar caminhos..." style="width:100%;padding:8px;margin-bottom:10px;border:1px solid #e2e8f0;border-radius:4px;">
    <table class="data-table" id="resultadosTable">
      <thead><tr><th>ID</th><th>Status</th><th>De</th><th>Para</th><th>Erro</th><th>Timestamp</th></tr></thead>
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
