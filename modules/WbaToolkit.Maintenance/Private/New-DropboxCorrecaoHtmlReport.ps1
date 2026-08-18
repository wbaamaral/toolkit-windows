#Requires -Version 5.1
<#
.SYNOPSIS
    Gera relatório HTML com o resultado da correção em massa de arquivos Dropbox.

.DESCRIPTION
    Constrói um relatório HTML claro e acionável a partir dos resultados de
    corrigir-arquivos-dropbox.ps1. Prioriza erros (seção primeiro), depois
    alterações bem-sucedidas, rollback e próximo passo.
    Delega o esqueleto HTML para New-ToolkitHtmlReport (WbaToolkit.Core).

.PARAMETER DropboxPath
    Caminho raiz do Dropbox analisado.

.PARAMETER Modo
    Tipo de correção aplicada: Renomeacao ou MudancaLocalizacao.

.PARAMETER Simular
    Se $true, indica que foi dry-run.

.PARAMETER TotalProcessados
    Total de itens processados.

.PARAMETER Corrigidos
    Número de correções bem-sucedidas.

.PARAMETER Erros
    Número de erros.

.PARAMETER SemAlteracao
    Número de itens sem alteração necessária.

.PARAMETER Simulados
    Número de itens simulados.

.PARAMETER ToolkitVersion
    Versão do toolkit.

.PARAMETER Resultados
    Lista de resultados (objetos com Status, Acao, Caminho, NovoPath, Erro, Mensagem).

.EXAMPLE
    $html = New-DropboxCorrecaoHtmlReport -DropboxPath 'C:\Dropbox' `
        -TotalProcessados 100 -Corrigidos 85 -Erros 15 -Resultados $resultados

.OUTPUTS
    System.String
    HTML completo pronto para gravação em arquivo.
#>
function New-DropboxCorrecaoHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DropboxPath,

        [Parameter(Mandatory = $false)]
        [string]$Modo = 'Renomeacao',

        [Parameter(Mandatory = $false)]
        [bool]$Simular = $false,

        [Parameter(Mandatory = $true)]
        [int]$TotalProcessados,

        [Parameter(Mandatory = $true)]
        [int]$Corrigidos,

        [Parameter(Mandatory = $true)]
        [int]$Erros,

        [Parameter(Mandatory = $false)]
        [int]$SemAlteracao = 0,

        [Parameter(Mandatory = $false)]
        [int]$Simulados = 0,

        [Parameter(Mandatory = $false)]
        [string]$ToolkitVersion = '',

        [Parameter(Mandatory = $false)]
        [object[]]$Resultados = @()
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $modoLabel = if ($Simular) { "$Modo (Simulacao)" } else { $Modo }

    # === Cards de resumo =====================================================
    $cards = @"
<div class="cards">
  <div class="card"><div class="card-label">Corrigidos</div><div class="card-value" style="color:var(--success)">$Corrigidos</div></div>
  <div class="card"><div class="card-label">Erros</div><div class="card-value" style="color:var(--danger)">$Erros</div></div>
  <div class="card"><div class="card-label">Sem alteracao</div><div class="card-value">$SemAlteracao</div></div>
  <div class="card"><div class="card-label">Modo</div><div class="card-value">$modoLabel</div><div class="card-sub">Total: $TotalProcessados</div></div>
</div>
"@

    $sections = ''

    # === Seção de ERROS (prioritária) ========================================
    $errosItems = @($Resultados | Where-Object { $_.Status -eq 'Erro' })
    if ($errosItems.Count -gt 0) {
        $erroRows = foreach ($r in $errosItems) {
            $id = [System.Net.WebUtility]::HtmlEncode("$($r.id)")
            $caminho = [System.Net.WebUtility]::HtmlEncode([string]$r.Caminho)
            $acao = [System.Net.WebUtility]::HtmlEncode([string]$r.Acao)
            $novoPath = if ($r.NovoPath) { [System.Net.WebUtility]::HtmlEncode([string]$r.NovoPath) } else { 'N/A' }
            $erro = if ($r.Erro) { [System.Net.WebUtility]::HtmlEncode([string]$r.Erro) } else { 'Erro desconhecido' }
            "<tr><td>$id</td><td class='mono'>$caminho</td><td>$acao</td><td class='mono small'>$novoPath</td><td>$erro</td></tr>"
        }

        $sections += @"
<div class="section">
  <div class="section-hdr" style="background:var(--danger)">[X] $($errosItems.Count) arquivo(s) nao puderam ser corrigidos</div>
  <div class="section-body">
    <input type="text" id="searchErros" onkeyup="filterTable('searchErros','errosTable')" placeholder="Pesquisar caminhos..." style="width:100%;padding:8px;margin-bottom:10px;border:1px solid #e2e8f0;border-radius:4px;">
    <table class="data-table" id="errosTable">
      <thead><tr><th>ID</th><th>Arquivo</th><th>Acao</th><th>De -&gt; Para Esperado</th><th>Causa do Erro</th></tr></thead>
      <tbody>
        $($erroRows -join "`n")
      </tbody>
    </table>
    <div class="alert" style="margin-top:1rem">
      <strong>Acao recomendada:</strong> Verifique se os arquivos estao acessiveis e nao estao em uso por outro processo.
      Execute novamente para tentar corrigir os itens que falharam.
    </div>
  </div>
</div>
"@
    }

    # === Seção de ALTERAÇÕES =================================================
    $alteracoesItems = @($Resultados | Where-Object { $_.Status -eq 'Corrigido' })
    if ($alteracoesItems.Count -gt 0) {
        $altRows = foreach ($r in $alteracoesItems) {
            $id = [System.Net.WebUtility]::HtmlEncode("$($r.id)")
            $de = [System.Net.WebUtility]::HtmlEncode([string]$r.Caminho)
            $para = [System.Net.WebUtility]::HtmlEncode([string]$r.NovoPath)
            $acao = [System.Net.WebUtility]::HtmlEncode([string]$r.Acao)
            "<tr><td>$id</td><td class='mono'>$de</td><td class='mono'>$para</td><td>$acao</td></tr>"
        }

        $sections += @"
<div class="section">
  <div class="section-hdr" style="background:var(--success)">[OK] $($alteracoesItems.Count) arquivo(s) corrigidos com sucesso</div>
  <div class="section-body">
    <input type="text" id="searchAlt" onkeyup="filterTable('searchAlt','altTable')" placeholder="Pesquisar caminhos..." style="width:100%;padding:8px;margin-bottom:10px;border:1px solid #e2e8f0;border-radius:4px;">
    <table class="data-table" id="altTable">
      <thead><tr><th>ID</th><th>De</th><th>Para</th><th>Acao</th></tr></thead>
      <tbody>
        $($altRows -join "`n")
      </tbody>
    </table>
  </div>
</div>
"@
    }

    # === Seção de ROLLBACK ===================================================
    if ($alteracoesItems.Count -gt 0 -and -not $Simular) {
        $sections += @"
<div class="section">
  <div class="section-hdr">[R] Como desfazer as alteracoes</div>
  <div class="section-body">
    <p>Para reverter as correcoes, use os backups salvos no diretorio <code>backups/</code>.</p>
    <p>O arquivo <code>rollback.json</code> contem o mapeamento de cada alteracao para reverter.</p>
  </div>
</div>
"@
    }

    # === Seção de SIMULAÇÃO ==================================================
    $simuladosItems = @($Resultados | Where-Object { $_.Status -eq 'Simulado' })
    if ($simuladosItems.Count -gt 0) {
        $simRows = foreach ($r in $simuladosItems) {
            $id = [System.Net.WebUtility]::HtmlEncode("$($r.id)")
            $de = [System.Net.WebUtility]::HtmlEncode([string]$r.Caminho)
            $para = [System.Net.WebUtility]::HtmlEncode([string]$r.NovoPath)
            $acao = [System.Net.WebUtility]::HtmlEncode([string]$r.Acao)
            "<tr><td>$id</td><td class='mono'>$de</td><td class='mono'>$para</td><td>$acao</td></tr>"
        }

        $sections += @"
<div class="section">
  <div class="section-hdr" style="background:var(--warning)">[?] $($simuladosItems.Count) alteracao(oes) simulada(s) (dry-run)</div>
  <div class="section-body">
    <p>Nenhuma alteracao foi aplicada. Revise a lista abaixo e execute sem <code>-Simular</code> para aplicar.</p>
    <input type="text" id="searchSim" onkeyup="filterTable('searchSim','simTable')" placeholder="Pesquisar caminhos..." style="width:100%;padding:8px;margin-bottom:10px;border:1px solid #e2e8f0;border-radius:4px;">
    <table class="data-table" id="simTable">
      <thead><tr><th>ID</th><th>De</th><th>Para</th><th>Acao</th></tr></thead>
      <tbody>
        $($simRows -join "`n")
      </tbody>
    </table>
  </div>
</div>
"@
    }

    # === Próximo passo =======================================================
    $proximoPasso = if ($Erros -gt 0) {
        @"
<div class="section">
  <div class="section-hdr">Proximo passo</div>
  <div class="section-body">
    <p>Revise os erros acima e execute novamente para os arquivos que falharam:</p>
    <code>.\scripts\corrigir-arquivos-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'</code>
    <p>Ou use <code>-Correcao MudancaLocalizacao</code> para mover os arquivos problematicos para uma pasta simplificada.</p>
  </div>
</div>
"@
    } elseif ($Simular) {
        @"
<div class="section">
  <div class="section-hdr">Proximo passo</div>
  <div class="section-body">
    <p>Para aplicar as correcoes simuladas, execute sem <code>-Simular</code>:</p>
    <code>.\scripts\corrigir-arquivos-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'</code>
  </div>
</div>
"@
    } else {
        @"
<div class="section">
  <div class="section-hdr">Proximo passo</div>
  <div class="section-body">
    <p>Todas as correcoes foram aplicadas com sucesso.</p>
    <p>Para normalizar os arquivos que ficaram com problemas, use:</p>
    <code>.\scripts\normalizar-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'</code>
  </div>
</div>
"@
    }

    # === JavaScript filtro ===================================================
    $jsFilter = @"
<script>
function filterTable(inputId, tableId) {
  var input = document.getElementById(inputId);
  var filter = input.value.toUpperCase();
  var table = document.getElementById(tableId);
  var tr = table.getElementsByTagName('tr');
  for (var i = 1; i < tr.length; i++) {
    var td = tr[i].getElementsByTagName('td')[1];
    if (td) {
      var txtValue = td.textContent || td.innerText;
      tr[i].style.display = txtValue.toUpperCase().indexOf(filter) > -1 ? '' : 'none';
    }
  }
}
</script>
"@

    # === Metadata ============================================================
    $metaRight = @(
        "Total: $TotalProcessados",
        "Corrigidos: $Corrigidos | Erros: $Erros",
        "Modo: $modoLabel",
        "Gerado: $timestamp"
    )
    if ($ToolkitVersion) {
        $metaRight += "Toolkit: $ToolkitVersion"
    }

    # === Montar body =========================================================
    $body = "$cards`n$sections`n$proximoPasso`n$jsFilter"

    return New-ToolkitHtmlReport `
        -Title 'Correcao de Arquivos Dropbox' `
        -Subtitle $DropboxPath `
        -Icon '&#128295;' `
        -MetaRight $metaRight `
        -Body $body `
        -ShowPrintButton
}
