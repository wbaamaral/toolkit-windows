# Projeto: wba-toolkit
# Autor: wbaamaral

function New-DropboxDoctorHtmlReport {
    <#
    .SYNOPSIS
        Monta o relatorio HTML do diagnostico de saude do cliente Dropbox.

    .DESCRIPTION
        Constroi cards de resumo e a tabela de checagens, e delega o esqueleto
        HTML (CSS, header, footer) para New-ToolkitHtmlReport (WbaToolkit.Core).
        Nao define CSS proprio -- reusa as classes ja definidas la
        (.cards, .card, .section, .data-table, .badge-*).

    .PARAMETER DropboxPath
        Caminho raiz do Dropbox analisado.

    .PARAMETER Score
        Pontuacao de saude (0-100).

    .PARAMETER Label
        Rotulo do resumo (Excelente/Bom/Degradado/Critico).

    .PARAMETER CriticalCount
        Quantidade de checagens em FALHA critica.

    .PARAMETER WarningCount
        Quantidade de checagens em AVISO.

    .PARAMETER Checks
        Lista de checagens (Categoria, Nome, Status, Detalhe, Recomendacao).

    .OUTPUTS
        System.String
        HTML completo pronto para gravacao em arquivo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DropboxPath,

        [Parameter(Mandatory = $true)]
        [int]$Score,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [int]$CriticalCount,

        [Parameter(Mandatory = $true)]
        [int]$WarningCount,

        [Parameter(Mandatory = $true)]
        [object[]]$Checks
    )

    $badgeClass = @{
        'OK'     = 'badge-green'
        'AVISO'  = 'badge-yellow'
        'FALHA'  = 'badge-red'
        'PULADO' = 'badge-gray'
    }

    $rows = foreach ($check in $Checks) {
        $cssClass = if ($badgeClass.ContainsKey([string]$check.Status)) { $badgeClass[[string]$check.Status] } else { 'badge-gray' }
        $categoria = [System.Net.WebUtility]::HtmlEncode([string]$check.Categoria)
        $nome = [System.Net.WebUtility]::HtmlEncode([string]$check.Nome)
        $status = [System.Net.WebUtility]::HtmlEncode([string]$check.Status)
        $detalhe = [System.Net.WebUtility]::HtmlEncode([string]$check.Detalhe)
        $recomendacao = [System.Net.WebUtility]::HtmlEncode([string]$check.Recomendacao)

        "<tr><td>$categoria</td><td>$nome</td><td><span class=`"badge $cssClass`">$status</span></td><td>$detalhe</td><td>$recomendacao</td></tr>"
    }

    # Processar arquivos problemáticos em uma tabela especial
    $problemFilesContent = ''
    $fileChecks = $Checks | Where-Object { $_.Nome -eq 'Nomes/caminhos problematicos' }
    if ($fileChecks.Count -gt 0) {
        $fileReport = $null
        # Tentar encontrar o FileReport no contexto - isso pode ser necessário em uma chamada real ao script
        $problemFilesContent = @"
<div class="section">
  <div class="section-hdr">Arquivos com Nomes/Caminhos Problemáticos</div>
  <div class="section-body">
    <p>Os seguintes itens foram identificados como problemáticos:</p>
    <input type="text" id="fileSearch" onkeyup="filterFiles()" placeholder="Pesquisar nomes/caminhos..." style="width: 100%; padding: 8px; margin-bottom: 10px;">
    <table class="data-table" id="problemFilesTable">
      <thead><tr><th>Caminho</th><th>Problemas Identificados</th></tr></thead>
      <tbody>
"@

        # Processando os arquivos problemáticos
        foreach ($check in $fileChecks) {
            $detalhe = [string]$check.Detalhe
            # Extrair a lista de problemas do detalhe
            if ($detalhe -match 'Exemplos: (.+)') {
                $examplesList = $matches[1]
                $examples = $examplesList -split ' \| '
                foreach ($example in $examples) {
                    if ($example -match '^(.+?) \((.+)\)$') {
                        $filePath = $matches[1]
                        $flags = $matches[2]
                        $problemFilesContent += "<tr><td class='file-path'>$filePath</td><td>$flags</td></tr>"
                    }
                }
            }
        }

        $problemFilesContent += @"
      </tbody>
    </table>
    <script>
      function filterFiles() {
        var input, filter, table, tr, td, i, txtValue;
        input = document.getElementById('fileSearch');
        filter = input.value.toUpperCase();
        table = document.getElementById('problemFilesTable');
        tr = table.getElementsByTagName('tr');
        for (i = 1; i < tr.length; i++) {
          td = tr[i].getElementsByTagName('td')[0];
          if (td) {
            txtValue = td.textContent || td.innerText;
            if (txtValue.toUpperCase().indexOf(filter) > -1) {
              tr[i].style.display = '';
            } else {
              tr[i].style.display = 'none';
            }
          }
        }
      }
    </script>
  </div>
</div>
"@
    }

    $encodedPath = [System.Net.WebUtility]::HtmlEncode($DropboxPath)

    $body = @"
<div class="cards">
  <div class="card"><div class="card-label">Pontuacao</div><div class="card-value">$Score/100</div><div class="card-sub">$Label</div></div>
  <div class="card"><div class="card-label">Falhas criticas</div><div class="card-value">$CriticalCount</div></div>
  <div class="card"><div class="card-label">Avisos</div><div class="card-value">$WarningCount</div></div>
  <div class="card"><div class="card-label">Pasta analisada</div><div class="card-value mono small">$encodedPath</div></div>
</div>
<div class="section">
  <div class="section-hdr">Checagens de saude</div>
  <div class="section-body">
    <table class="data-table">
      <thead><tr><th>Categoria</th><th>Checagem</th><th>Status</th><th>Detalhe</th><th>Recomendacao</th></tr></thead>
      <tbody>
$($rows -join "`r`n")
      </tbody>
    </table>
  </div>
</div>
$problemFilesContent
"@

    return New-ToolkitHtmlReport `
        -Title 'Diagnostico do Cliente Dropbox' `
        -Subtitle $DropboxPath `
        -Icon '&#128229;' `
        -MetaRight @("Pontuacao: $Score/100", "Status: $Label") `
        -Body $body
}
