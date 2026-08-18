#Requires -Version 5.1
<#
.SYNOPSIS
    Normaliza arquivos problemáticos do Dropbox com fluxo iterativo controlado.

.DESCRIPTION
    Ferramenta completa de normalização que implementa um fluxo iterativo:
    1. Carrega diagnóstico de arquivos problemáticos (JSON)
    2. Gera propostas de correção (TUI interativa ou automática)
    3. Valida propostas via relatório HTML
    4. Aplica correções após confirmação
    5. Gera relatorio detalhado de resultado (de -> para)

    Quando encurtar apenas o diretório mais profundo não é suficiente para o
    caminho completo caber no limite, a proposta é encadeada: sobe-se para o
    diretório ancestral e repete-se o encurtamento nesse nível, até caber ou
    até atingir a raiz protegida. A aplicação (-Modo Aplicar) renomeia essa
    cadeia sempre do nível mais raso para o mais profundo.

    Na TUI, o comando "E <id>" permite editar manualmente o nome proposto
    para o nível mais profundo de um diretório (em vez de aceitar apenas a
    sugestão automática), validando caracteres inválidos e mostrando o
    comprimento do caminho resultante antes de confirmar.

    O relatório HTML de proposta (correcoes-propostas.html) também é
    editável no navegador: cada linha tem checkbox de seleção e campo de
    texto para o nome proposto, com recálculo ao vivo do comprimento do
    caminho e um botão "Baixar JSON corrigido" que gera um arquivo pronto
    para reinjeção em -Modo Aplicar -PropostaFile.

    Este script e a FASE 2 do ciclo de normalizacao do Dropbox:

      diagnosticar-dropbox.ps1 -ExportarJson        (gera JSON)
                ↓
      normalizar-dropbox.ps1                         (TUI interativa)
                ↓
      correcoes-propostas.json + HTML                (validacao)
                ↓
      normalizar-dropbox.ps1 -Modo Aplicar           (aplica correcoes)
                ↓
      correcoes-aplicadas.json + HTML (de -> para)    (resultado)

.PARAMETER InputFile
    Arquivo JSON com a lista de arquivos problemáticos gerado pelo
    diagnosticar-dropbox.ps1 -ExportarJson.

.PARAMETER Modo
    Modo de operação:
    - TUI: Interface interativa para seleção/edição de propostas
    - Proposta: Gera proposta sem interação (todos selecionados)
    - Aplicar: Aplica proposta de um arquivo JSON
    - Relatorio: Gera relatório HTML de uma proposta ou resultado

.PARAMETER PropostaFile
    Arquivo JSON com a proposta (necessário para modos Aplicar e Relatorio).

.PARAMETER ResultadoFile
    Arquivo JSON com o resultado (necessário para modo Relatorio com resultado).

.PARAMETER DiretorioSaida
    Diretório onde serão salvos os arquivos gerados.

.PARAMETER PageSize
    Número de itens por página na TUI. Padrão: 50.

.PARAMETER LimiteCaminho
    Comprimento máximo de caminho tolerado ao propor o encadeamento de
    encurtamento de diretórios. Padrão: 260 (limite clássico do Windows sem
    long paths habilitado).

.PARAMETER MargemSeguranca
    Caracteres reservados como margem de segurança, subtraídos de
    -LimiteCaminho para formar o alvo real de encurtamento. Padrão: 10.

.PARAMETER NonInteractive
    Gera proposta sem TUI, com todos os itens selecionados.

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\normalizar-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'

    Modo TUI interativo -- selecione/edite propostas antes de aplicar.

.EXAMPLE
    .\normalizar-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json' -Modo Proposta -NonInteractive

    Gera proposta automaticamente (todos selecionados) sem TUI.

.EXAMPLE
    .\normalizar-dropbox.ps1 -Modo Aplicar -PropostaFile '.\correcoes-propostas.json'

    Aplica proposta após validação.

.EXAMPLE
    .\normalizar-dropbox.ps1 -Modo Relatorio -PropostaFile '.\correcoes-propostas.json'

    Gera relatório HTML de uma proposta.

.EXAMPLE
    .\normalizar-dropbox.ps1 -Modo Relatorio -ResultadoFile '.\correcoes-aplicadas.json'

    Gera relatório HTML de um resultado já aplicado.

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.Maintenance.

    Ciclo de normalizacao:
      1. diagnosticar-dropbox.ps1 -ExportarJson    (gera JSON)
      2. normalizar-dropbox.ps1                    (TUI interativa)
      3. normalizar-dropbox.ps1 -Modo Aplicar      (aplica correcoes)

    Saida (TUI/Proposta):
      correcoes-propostas.json : proposta de correcoes
      correcoes-propostas.html : relatorio visual da proposta

    Saida (Aplicar):
      correcoes-aplicadas.json : resultado detalhado (de -> para)
      correcoes-aplicadas.html : relatorio visual do resultado

    Ciclo do editor HTML interativo (correcoes-propostas.html):
      1. Gerar a proposta (TUI ou -Modo Proposta)
      2. Abrir correcoes-propostas.html num navegador
      3. Marcar/desmarcar linhas e editar o nome proposto (o comprimento do
         caminho resultante e recalculado ao digitar, ok/excede)
      4. Clicar em "Baixar JSON corrigido" -- gera um novo arquivo JSON
      5. Reaplicar com: normalizar-dropbox.ps1 -Modo Aplicar -PropostaFile '<json-corrigido>'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet('TUI', 'Proposta', 'Aplicar', 'Relatorio')]
    [string]$Modo = 'TUI',

    [Parameter(Mandatory = $false)]
    [string]$PropostaFile,

    [Parameter(Mandatory = $false)]
    [string]$ResultadoFile,

    [Parameter(Mandatory = $false)]
    [string]$DiretorioSaida,

    [Parameter(Mandatory = $false)]
    [int]$PageSize = 50,

    [Parameter(Mandatory = $false)]
    [int]$LimiteCaminho = 260,

    [Parameter(Mandatory = $false)]
    [int]$MargemSeguranca = 10,

    [switch]$NonInteractive,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null }
catch { Write-Verbose "Nao foi possivel ajustar a pagina de codigo do console para UTF-8: $($_.Exception.Message)" }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Normalização de Arquivos Dropbox" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -InputFile '<arquivo>'      Arquivo JSON do diagnóstico."
    Write-Host "  -Modo '<modo>'               TUI (padrao), Proposta, Aplicar ou Relatorio."
    Write-Host "  -PropostaFile '<arquivo>'    Arquivo JSON da proposta (para Aplicar/Relatorio)."
    Write-Host "  -ResultadoFile '<arquivo>'   Arquivo JSON do resultado (para Relatorio)."
    Write-Host "  -DiretorioSaida '<dir>'      Diretorio de saida para arquivos gerados."
    Write-Host "  -PageSize <n>                Itens por pagina na TUI (padrao: 50)."
    Write-Host "  -LimiteCaminho <n>           Comprimento maximo de caminho tolerado (padrao: 260)."
    Write-Host "  -MargemSeguranca <n>         Margem de seguranca subtraida do limite (padrao: 10)."
    Write-Host "  -NonInteractive              Gera proposta sem TUI."
    Write-Host "  -Help                        Esta ajuda."
    Write-Host ""
    Write-Host "Modos:"
    Write-Host "  TUI          Interface interativa para selecionar/editar propostas (padrao)."
    Write-Host "  Proposta     Gera proposta sem interacao (todos selecionados)."
    Write-Host "  Aplicar      Aplica proposta de um arquivo JSON."
    Write-Host "  Relatorio    Gera relatorio HTML de uma proposta ou resultado."
    Write-Host ""
    Write-Host "Comandos da TUI:"
    Write-Host "  [1-9] Selecionar/deselecionar diretorio     [T]odos  [N]enhum"
    Write-Host "  [V]er detalhes    [E <id>] Editar nome proposto manualmente"
    Write-Host "  [G]erar proposta  [Q]uit"
    Write-Host ""
    Write-Host "Ciclo de normalizacao:"
    Write-Host "  1. diagnosticar-dropbox.ps1 -ExportarJson    (gera JSON)"
    Write-Host "  2. normalizar-dropbox.ps1                    (TUI interativa)"
    Write-Host "  3. normalizar-dropbox.ps1 -Modo Aplicar      (aplica correcoes)"
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName -InputFile '.\diagnostico-dropbox.json'"
    Write-Host "  .\$ScriptName -InputFile '.\diagnostico-dropbox.json' -Modo Proposta -NonInteractive"
    Write-Host "  .\$ScriptName -Modo Aplicar -PropostaFile '.\correcoes-propostas.json'"
    Write-Host "  .\$ScriptName -Modo Relatorio -PropostaFile '.\correcoes-propostas.json'"
    Write-Host "  .\$ScriptName -Modo Relatorio -ResultadoFile '.\correcoes-aplicadas.json'"
    Write-Host ""
}

# Despacha -Help antes de qualquer verificacao de modulo ou elevacao (ADR 0021).
if ($Help) { Show-Help; exit 0 }

# === Dependencias: adicionar modules/ ao PSModulePath (padrao-dependencias-modulos.md) ===
$moduleRoot = Join-Path $ToolkitRoot 'modules'
if ($env:PSModulePath -notlike "*$moduleRoot*") {
    $env:PSModulePath = "$moduleRoot;$env:PSModulePath"
}

$coreModuleRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$maintModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Maintenance'

foreach ($mod in @($coreModuleRoot, $maintModuleRoot)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        Write-Host "        Solucao: verifique o clone do repositorio em $ToolkitRoot" -ForegroundColor Yellow
        exit 1
    }
}

try {
    foreach ($modRoot in @($coreModuleRoot, $maintModuleRoot)) {
        foreach ($sub in @('Private', 'Public')) {
            $dir = Join-Path $modRoot $sub
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction Stop | ForEach-Object { . $_.FullName }
            }
        }
    }
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos do toolkit." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "        Solucao: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force" -ForegroundColor Yellow
    exit 1
}

# === Funcoes auxiliares ===================================================
# Get-DiretoriosProblematicos foi extraida para funcao privada testavel do
# modulo WbaToolkit.Maintenance (Private/Get-DiretoriosProblematicos.ps1).
# Ela e carregada pelo dot-source acima e implementa o encadeamento real de
# encurtamento (recalcula o comprimento do caminho completo e sobe niveis
# ate caber ou atingir -CaminhoRaiz).

function Show-TUI {
    <#
    .SYNOPSIS
        Exibe interface TUI agrupada por diretório com antes/depois.
    .DESCRIPTION
        Mostra diretórios problemáticos, não arquivos individuais.
        Para cada diretório, mostra: problema, quantidade de itens, antes/depois.
        Operador escolhe por diretório (não por arquivo).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Diretorios,
        [Parameter(Mandatory = $true)]
        [string]$DropboxPath
    )

    $totalDirs = $Diretorios.Count
    $dirsComProblema = @($Diretorios | Where-Object { -not $_.ja_valido }).Count

    while ($true) {
        Clear-Host
        Write-Host "=== Normalizacao de Diretorios Dropbox ===" -ForegroundColor Cyan
        Write-Host "Pasta: $DropboxPath"
        Write-Host "Diretorios: $totalDirs analisados | $dirsComProblema com problemas"
        Write-Host ""

        # Tabela de diretórios
        Write-Host (" {0,-4} | {1,-6} | {2,-50} | {3,-8} | {4}" -f 'ID', 'Status', 'Diretorio', 'Itens', 'Problema')
        Write-Host ("-" * 4 + "-+-" + "-" * 6 + "-+-" + "-" * 50 + "-+-" + "-" * 8 + "-+-" + "-" * 25)

        foreach ($d in $Diretorios) {
            $naoResolvido = ($d.atingiu_raiz -and -not $d.resolvido)
            $status = if ($d.ja_valido) { '[OK]' } elseif ($naoResolvido) { '[!!]' } elseif ($d.selecionado) { '[X]' } else { '[ ]' }
            $statusColor = if ($d.ja_valido) { 'Gray' } elseif ($naoResolvido) { 'Magenta' } elseif ($d.selecionado) { 'Green' } else { 'Red' }
            $dirDisplay = if ($d.diretorio.Length -gt 50) {
                '...' + $d.diretorio.Substring($d.diretorio.Length - 47)
            } else {
                $d.diretorio
            }
            $problemaDisplay = $d.problema_pred
            if ($d.cadeia -and @($d.cadeia).Count -gt 1) { $problemaDisplay = "$problemaDisplay (cadeia: $(@($d.cadeia).Count) niveis)" }
            if ($naoResolvido) { $problemaDisplay = "$problemaDisplay - NAO RESOLVIDO, edite manualmente" }

            Write-Host (" {0,-4} | " -f $d.id) -NoNewline
            Write-Host ("{0,-6}" -f $status) -ForegroundColor $statusColor -NoNewline
            Write-Host (" | {0,-50} | {1,-8} | {2}" -f $dirDisplay, $d.total_arquivos, $problemaDisplay)
        }

        Write-Host ""
        Write-Host "Comandos:" -ForegroundColor Cyan
        Write-Host "  [1-9] Selecionar/deselecionar diretorio"
        Write-Host "  [T]odos  [N]enhum"
        Write-Host "  [V]er detalhes de um diretorio"
        Write-Host "  [E <id>] Editar nome proposto manualmente"
        Write-Host "  [G]erar proposta  [Q]uit"
        Write-Host ""

        $cmd = Read-Host "Comando"
        $cmd = $cmd.Trim().ToUpper()

        switch -Regex ($cmd) {
            '^(\d+)$' {
                $id = [int]$Matches[1]
                $dir = $Diretorios | Where-Object { $_.id -eq $id }
                if ($dir -and -not $dir.ja_valido) {
                    $dir.selecionado = -not $dir.selecionado
                    $dirsComProblema = @($Diretorios | Where-Object { -not $_.ja_valido -and $_.selecionado }).Count
                    $estado = if ($dir.selecionado) { 'selecionado' } else { 'deselecionado' }
                    Write-Host "Diretorio $id $estado" -ForegroundColor $(if ($dir.selecionado) { 'Green' } else { 'Yellow' })
                }
                Start-Sleep -Milliseconds 500
            }
            '^T$' {
                foreach ($d in $Diretorios) { if (-not $d.ja_valido) { $d.selecionado = $true } }
                $dirsComProblema = @($Diretorios | Where-Object { -not $_.ja_valido -and $_.selecionado }).Count
                Write-Host "Todos selecionados" -ForegroundColor Green
                Start-Sleep -Milliseconds 500
            }
            '^N$' {
                foreach ($d in $Diretorios) { $d.selecionado = $false }
                $dirsComProblema = 0
                Write-Host "Nenhum selecionado" -ForegroundColor Yellow
                Start-Sleep -Milliseconds 500
            }
            '^V\s*(\d+)$' {
                $id = [int]$Matches[1]
                $dir = $Diretorios | Where-Object { $_.id -eq $id }
                if ($dir) {
                    Clear-Host
                    Write-Host "=== Detalhes do Diretorio $id ===" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Diretorio atual:" -ForegroundColor Yellow
                    Write-Host "  $($dir.caminho_original)" -ForegroundColor White
                    Write-Host ""
                    Write-Host "Diretorio proposto:" -ForegroundColor Yellow
                    Write-Host "  $($dir.caminho_proposto)" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "Arquivos afetados: $($dir.total_arquivos)" -ForegroundColor Cyan
                    Write-Host ""
                    if ($dir.cadeia -and @($dir.cadeia).Count -gt 1) {
                        Write-Host "Cadeia de encurtamento (raso -> profundo):" -ForegroundColor Yellow
                        foreach ($nivelItem in @($dir.cadeia)) {
                            Write-Host ("  Nivel $($nivelItem.nivel): $($nivelItem.caminho_original) -> $($nivelItem.nome_proposto)") -ForegroundColor White
                        }
                        Write-Host ""
                    }
                    if ($dir.atingiu_raiz -and -not $dir.resolvido) {
                        Write-Warn "Nao foi possivel encurtar automaticamente ate a raiz protegida. Use [E $id] para editar manualmente."
                        Write-Host ""
                    }
                    Write-Host "Problemas encontrados:" -ForegroundColor Yellow
                    foreach ($p in $dir.problemas.GetEnumerator()) {
                        Write-Host "  $($p.Key): $($p.Value) arquivo(s)" -ForegroundColor White
                    }
                    Write-Host ""
                    Read-Host "Pressione Enter para voltar"
                }
            }
            '^E\s*(\d+)$' {
                $id = [int]$Matches[1]
                $dir = $Diretorios | Where-Object { $_.id -eq $id }
                if (-not $dir) {
                    Write-Warn "Diretorio $id nao encontrado."
                    Start-Sleep -Milliseconds 1000
                }
                else {
                    Clear-Host
                    Write-Host "=== Editar nome proposto - Diretorio $id ===" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Diretorio atual : $($dir.diretorio)" -ForegroundColor White
                    Write-Host "Nome proposto atual (nivel mais profundo): $($dir.nome_proposto)" -ForegroundColor Yellow
                    Write-Host ""

                    $prefixoAncestral = Split-Path -Parent $dir.caminho_proposto
                    $novoNome = Read-UserInput -Question "Novo nome para o diretorio mais profundo" -DefaultValue $dir.nome_proposto

                    $nomeValidado = Get-SafeFileName -Name $novoNome
                    if ($nomeValidado -ne $novoNome) {
                        Write-Warn "Nome contem caracteres invalidos ou precisou de ajuste. Sugestao corrigida: $nomeValidado"
                        $novoNome = $nomeValidado
                    }

                    $novoCaminhoDir = Join-Path $prefixoAncestral $novoNome
                    $comprimentoResultante = $novoCaminhoDir.Length + $dir.maior_sufixo
                    $cabe = $comprimentoResultante -le $LimiteCaminho

                    Write-Host ""
                    Write-Host "Diretorio resultante : $novoCaminhoDir"
                    Write-Host -NoNewline "Comprimento maximo resultante (arquivo mais longo do diretorio): "
                    Write-Host "$comprimentoResultante / $LimiteCaminho" -ForegroundColor $(if ($cabe) { 'Green' } else { 'Red' })
                    if (-not $cabe) {
                        Write-Warn "O caminho resultante ainda ultrapassa o limite configurado."
                    }
                    Write-Host ""

                    $confirmar = Read-YesNo -Question "Confirma este nome para o diretorio $id?" -DefaultYes $cabe
                    if ($confirmar) {
                        $dir.nome_proposto = $novoNome
                        $dir.caminho_proposto = $novoCaminhoDir
                        $dir.editado_manualmente = $true
                        $dir.selecionado = $true
                        $dir.ja_valido = $false
                        if ($dir.cadeia -and @($dir.cadeia).Count -gt 0) {
                            $cadeiaLista = @($dir.cadeia)
                            $cadeiaLista[$cadeiaLista.Count - 1].nome_proposto = $novoNome
                            $dir.cadeia = $cadeiaLista
                        }
                        Write-Ok "Nome do diretorio $id atualizado manualmente."
                    }
                    else {
                        Write-Host "Edicao descartada." -ForegroundColor Yellow
                    }
                    Start-Sleep -Milliseconds 800
                }
            }
            '^G$' {
                $selecionados = @($Diretorios | Where-Object { $_.selecionado -and -not $_.ja_valido })
                if ($selecionados.Count -eq 0) {
                    Write-Host "Nenhum diretorio selecionado." -ForegroundColor Yellow
                    Start-Sleep -Milliseconds 1000
                } else {
                    return $Diretorios
                }
            }
            '^Q$' {
                Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Yellow
                return $null
            }
        }
    }
}

# === Validação de parâmetros ==============================================

if ($Modo -in @('Aplicar', 'Relatorio') -and [string]::IsNullOrWhiteSpace($PropostaFile)) {
    Write-Fail "Modo $Modo requer -PropostaFile."
    exit 1
}

if ($Modo -eq 'Relatorio' -and [string]::IsNullOrWhiteSpace($ResultadoFile) -and [string]::IsNullOrWhiteSpace($PropostaFile)) {
    Write-Fail "Modo Relatorio requer -PropostaFile ou -ResultadoFile."
    exit 1
}

# === Processamento principal ==============================================

Write-Title "Normalização de Arquivos Dropbox"

# Modo Proposta: gerar proposta do diagnóstico
if ($Modo -in @('TUI', 'Proposta')) {
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        Write-Fail "Modos TUI e Proposta requerem -InputFile."
        exit 1
    }

    # Carregar diagnóstico
    $InputFile = [System.IO.Path]::GetFullPath($InputFile)
    if (-not (Test-Path -LiteralPath $InputFile)) {
        Write-Fail "Arquivo de entrada nao encontrado: $InputFile"
        exit 1
    }

    try {
        $jsonData = Get-Content -LiteralPath $InputFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Fail "Nao foi possivel carregar o arquivo JSON: $($_.Exception.Message)"
        exit 1
    }

    if (-not ($jsonData -and $jsonData.arquivos_problematicos)) {
        Write-Fail "Estrutura do arquivo invalida. Nenhum dado de arquivos problematicos encontrado."
        exit 1
    }

    $dropboxPath = $jsonData.metadata.caminho_analisado
    Write-Ok "Arquivo carregado com sucesso: $dropboxPath"
    Write-Info "Total de arquivos problematicos: $($jsonData.arquivos_problematicos.Count)"

    # Agrupar por diretorio
    Write-Host ''
    Write-Title "Analisando diretorios problematicos"

    $diretorios = Get-DiretoriosProblematicos -Arquivos $jsonData.arquivos_problematicos `
        -CaminhoRaiz $dropboxPath -LimiteCaminho $LimiteCaminho -MargemSeguranca $MargemSeguranca
    $dirsComProblema = @($diretorios | Where-Object { -not $_.ja_valido }).Count
    $totalArquivos = @($diretorios | ForEach-Object { $_.total_arquivos } | Measure-Object -Sum).Sum
    $naoResolvidos = @($diretorios | Where-Object { $_.atingiu_raiz -and -not $_.resolvido }).Count

    Write-Ok "Diretorios analisados: $(@($diretorios).Count)"
    Write-Info "Diretorios com problemas: $dirsComProblema"
    Write-Info "Total de arquivos afetados: $totalArquivos"
    if ($naoResolvidos -gt 0) {
        Write-Warn "Diretorios que nao couberam automaticamente ate a raiz protegida: $naoResolvidos (edite manualmente na TUI ou no HTML)"
    }

    # TUI ou NonInteractive
    if ($Modo -eq 'TUI' -and -not $NonInteractive) {
        $diretorios = Show-TUI -Diretorios $diretorios -DropboxPath $dropboxPath
        if ($null -eq $diretorios) {
            Write-Host "Operacao cancelada." -ForegroundColor Yellow
            exit 0
        }
        $dirsComProblema = @($diretorios | Where-Object { -not $_.ja_valido -and $_.selecionado }).Count
    }
    else {
        # NonInteractive: selecionar todos automaticamente
        foreach ($d in $diretorios) { $d.selecionado = (-not $d.ja_valido) }
    }

    # Configurar diretorio de saida
    if ([string]::IsNullOrWhiteSpace($DiretorioSaida)) {
        $DiretorioSaida = Join-Path (Split-Path -Parent $InputFile) 'normalizacao'
    }
    else {
        $DiretorioSaida = [System.IO.Path]::GetFullPath($DiretorioSaida)
    }

    if (-not (Test-Path -LiteralPath $DiretorioSaida -PathType Container)) {
        New-Item -ItemType Directory -Path $DiretorioSaida -Force | Out-Null
    }

    $propostaJsonPath = Join-Path $DiretorioSaida 'correcoes-propostas.json'
    Write-Info "Gerando proposta em: $propostaJsonPath"

    # Agrupar arquivos por diretorio pai uma unica vez (O(arquivos)) em vez de
    # revarrer a lista inteira para cada diretorio selecionado (O(diretorios x
    # arquivos) -- com centenas de diretorios e milhares de arquivos isso levava
    # minutos sem nenhum indicador de progresso na tela).
    $arquivosPorDiretorio = @{}
    foreach ($arq in $jsonData.arquivos_problematicos) {
        $dirPai = Split-Path -Parent ([string]$arq.Caminho)
        if (-not $arquivosPorDiretorio.ContainsKey($dirPai)) {
            $arquivosPorDiretorio[$dirPai] = New-Object System.Collections.Generic.List[object]
        }
        [void]$arquivosPorDiretorio[$dirPai].Add($arq)
    }

    # Gerar proposta (expandir diretorios selecionados em arquivos individuais)
    $propostas = New-Object System.Collections.Generic.List[pscustomobject]
    $diretoriosSelecionados = @($diretorios | Where-Object { $_.selecionado })
    $id = 1
    $contadorDir = 0
    foreach ($dir in $diretoriosSelecionados) {
        $contadorDir++
        if ($diretoriosSelecionados.Count -gt 20) {
            Write-Step "Gerando proposta: diretorio $contadorDir de $($diretoriosSelecionados.Count)" ([math]::Round(($contadorDir / $diretoriosSelecionados.Count) * 100))
        }
        $arquivosDoDir = if ($arquivosPorDiretorio.ContainsKey($dir.diretorio)) {
            $arquivosPorDiretorio[$dir.diretorio]
        }
        else {
            @()
        }
        foreach ($arq in $arquivosDoDir) {
            $nome = [string]$arq.Nome
            if ([string]::IsNullOrWhiteSpace($nome)) { $nome = Split-Path -Leaf ([string]$arq.Caminho) }
            [void]$propostas.Add([pscustomobject]@{
                id               = $id
                diretorio_id     = $dir.id
                caminho_original = [string]$arq.Caminho
                nome_original    = $nome
                tipo_correcao    = 'Renomeacao'
                selecionado      = $true
            })
            $id++
        }
    }

    $totalPropostas = $propostas.Count
    Write-Host ''
    Write-Title "Proposta gerada"
    Write-Ok "Arquivos a corrigir: $totalPropostas (em $dirsComProblema diretorios)"

    # Confirmar antes de salvar
    if ($Modo -eq 'TUI' -and -not $NonInteractive) {
        $confirm = Read-YesNo -Question "Confirma a proposta de correcao de $totalPropostas arquivos?" -DefaultYes $true
        if (-not $confirm) {
            Write-Host "Operacao cancelada." -ForegroundColor Yellow
            exit 0
        }
    }

    # Salvar JSON de proposta
    $propostaJson = [pscustomobject]@{
        metadata = [pscustomobject]@{
            data_geracao       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            versao_toolkit     = 'v1.0.0'
            diagnostico_origem = $InputFile
            total_propostas    = $totalPropostas
            diretorios         = $dirsComProblema
        }
        diretorios = @($diretorios | Where-Object { $_.selecionado } | ForEach-Object {
            [pscustomobject]@{
                id                  = $_.id
                diretorio           = $_.diretorio
                nome_original       = $_.nome_original
                nome_proposto       = $_.nome_proposto
                caminho_original    = $_.caminho_original
                caminho_proposto    = $_.caminho_proposto
                total_arquivos      = $_.total_arquivos
                maior_sufixo        = $_.maior_sufixo
                problemas           = $_.problemas
                problema_pred       = $_.problema_pred
                selecionado         = $_.selecionado
                resolvido           = $_.resolvido
                atingiu_raiz        = $_.atingiu_raiz
                editado_manualmente = $_.editado_manualmente
                cadeia              = @($_.cadeia)
            }
        })
        propostas = $propostas.ToArray()
    }

    Write-TextFileUtf8 -Path $propostaJsonPath -Content ($propostaJson | ConvertTo-Json -Depth 6)
    Write-Ok "Proposta salva em: $propostaJsonPath"

    # Gerar tambem o HTML da proposta na mesma chamada (evita um passo -Modo
    # Relatorio separado -- mesmo padrao que -Modo Aplicar ja usa para o
    # relatorio de resultado).
    $propostaHtmlPath = Join-Path $DiretorioSaida 'correcoes-propostas.html'
    $propostaHtml = New-DropboxPropostaHtmlReport -DropboxPath $dropboxPath `
        -TotalPropostas $totalPropostas -Selecionadas $totalPropostas -Propostas $propostaJson.propostas `
        -Diretorios $propostaJson.diretorios -MetadataOriginal $propostaJson.metadata -LimiteCaminho $LimiteCaminho
    Write-TextFileUtf8 -Path $propostaHtmlPath -Content $propostaHtml
    Write-Ok "Relatorio HTML gerado: $propostaHtmlPath"

    # Resumo
    Write-Host ''
    Write-Title "Resumo"
    foreach ($dir in ($diretorios | Where-Object { $_.selecionado })) {
        Write-Info "  $($dir.nome_original) -> $($dir.nome_proposto) ($($dir.total_arquivos) arquivos)"
    }
    Write-Host ''
    Write-Info "Proposta JSON : $propostaJsonPath"
    Write-Info "Proposta HTML : $propostaHtmlPath"
    Write-Host ''
    Write-Info "Proximo passo: revise a proposta (JSON ou HTML) e aplique com -Modo Aplicar -PropostaFile '$propostaJsonPath'"
}

# Modo Aplicar: aplicar proposta (por diretorios)
elseif ($Modo -eq 'Aplicar') {
    $PropostaFile = [System.IO.Path]::GetFullPath($PropostaFile)
    if (-not (Test-Path -LiteralPath $PropostaFile)) {
        Write-Fail "Arquivo de proposta nao encontrado: $PropostaFile"
        exit 1
    }

    try {
        $propostaData = Get-Content -LiteralPath $PropostaFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Fail "Nao foi possivel carregar o arquivo de proposta: $($_.Exception.Message)"
        exit 1
    }

    if (-not ($propostaData -and $propostaData.diretorios)) {
        Write-Fail "Estrutura do arquivo invalida. Nenhum dado de diretorios encontrado."
        exit 1
    }

    $dropboxPath = $propostaData.metadata.diagnostico_origem
    $diretoriosParaAplicar = @($propostaData.diretorios | Where-Object { $_.selecionado })

    Write-Info "Proposta carregada: $PropostaFile"
    Write-Info "Diretorios selecionados: $($diretoriosParaAplicar.Count)"

    if ($diretoriosParaAplicar.Count -eq 0) {
        Write-Warn "Nenhum diretorio selecionado para aplicacao."
        exit 0
    }

    # Cadeia efetiva por diretorio: usa a cadeia do JSON quando presente
    # (proposta gerada apos esta tarefa); sintetiza uma cadeia de 1 nivel
    # para JSON antigo (compatibilidade com propostas geradas antes do
    # encadeamento).
    foreach ($d in $diretoriosParaAplicar) {
        $cadeiaEfetiva = if ($d.PSObject.Properties['cadeia'] -and @($d.cadeia).Count -gt 0) {
            @($d.cadeia)
        }
        else {
            @([pscustomobject]@{ nivel = 1; caminho_original = $d.diretorio; nome_proposto = $d.nome_proposto })
        }
        Add-Member -InputObject $d -MemberType NoteProperty -Name '_cadeiaEfetiva' -Value $cadeiaEfetiva -Force
    }

    # Mostrar antes/depois (antes de confirmar)
    Write-Host ''
    Write-Title "Correcoes a aplicar"
    foreach ($d in $diretoriosParaAplicar) {
        $cadeiaOrdenada = @($d._cadeiaEfetiva | Sort-Object nivel)
        $dirNovo = Split-Path -Parent $cadeiaOrdenada[0].caminho_original
        foreach ($nivelItem in $cadeiaOrdenada) { $dirNovo = Join-Path $dirNovo $nivelItem.nome_proposto }

        Write-Host "  De : " -NoNewline
        Write-Host "$($d.diretorio)" -ForegroundColor Red
        Write-Host "  Para: " -NoNewline
        Write-Host "$dirNovo" -ForegroundColor Green
        Write-Host "  Itens: $($d.total_arquivos)" -ForegroundColor Cyan
        if ($cadeiaOrdenada.Count -gt 1) {
            Write-Host "  Cadeia ($($cadeiaOrdenada.Count) niveis, raso -> profundo):" -ForegroundColor Yellow
            foreach ($nivelItem in $cadeiaOrdenada) {
                Write-Host "    Nivel $($nivelItem.nivel): $(Split-Path -Leaf $nivelItem.caminho_original) -> $($nivelItem.nome_proposto)"
            }
        }
        Write-Host ''
    }

    # Confirmar
    if (-not $NonInteractive) {
        $confirm = Read-YesNo -Question "Confirma a aplicacao das correcoes acima?" -DefaultYes $false
        if (-not $confirm) {
            Write-Host "Operacao cancelada." -ForegroundColor Yellow
            exit 0
        }
    }

    # Configurar diretorio de saida
    if ([string]::IsNullOrWhiteSpace($DiretorioSaida)) {
        $DiretorioSaida = Join-Path (Split-Path -Parent $PropostaFile) 'aplicacao'
    }
    else {
        $DiretorioSaida = [System.IO.Path]::GetFullPath($DiretorioSaida)
    }

    if (-not (Test-Path -LiteralPath $DiretorioSaida -PathType Container)) {
        New-Item -ItemType Directory -Path $DiretorioSaida -Force | Out-Null
    }

    # Aplicar correcoes (rename de diretorios)
    Write-Host ''
    Write-Title "Aplicando correcoes"

    $resultados = New-Object System.Collections.Generic.List[pscustomobject]
    $contador = 0
    $totalArquivosAfetados = 0

    foreach ($dir in $diretoriosParaAplicar) {
        $contador++
        $cadeiaOrdenada = @($dir._cadeiaEfetiva | Sort-Object nivel)
        $nomeNovoProfundo = $cadeiaOrdenada[$cadeiaOrdenada.Count - 1].nome_proposto

        Write-Step "Processando diretorio $contador de $($diretoriosParaAplicar.Count)" ([math]::Round(($contador / $diretoriosParaAplicar.Count) * 100))

        $aplicacaoCadeia = Invoke-DropboxCadeiaRename -Cadeia $cadeiaOrdenada

        $resultado = [pscustomobject]@{
            id                = $dir.id
            diretorio_origem  = $dir.diretorio
            diretorio_destino = $aplicacaoCadeia.caminho_final
            nome_original     = $dir.nome_original
            nome_novo         = $nomeNovoProfundo
            arquivos_afetados = $dir.total_arquivos
            status            = if ($aplicacaoCadeia.sucesso) { 'Sucesso' } else { 'Erro' }
            erro              = $aplicacaoCadeia.erro
            timestamp         = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            cadeia            = $aplicacaoCadeia.niveis
        }

        if ($aplicacaoCadeia.sucesso) {
            $totalArquivosAfetados += $dir.total_arquivos
            Write-Ok "$($dir.nome_original) -> $nomeNovoProfundo ($($dir.total_arquivos) arquivos, $($cadeiaOrdenada.Count) nivel(is))"
        }
        else {
            Write-Fail "$($dir.nome_original): $($aplicacaoCadeia.erro)"
        }

        [void]$resultados.Add($resultado)
    }

    $sucesso = @($resultados | Where-Object { $_.status -eq 'Sucesso' }).Count
    $falha = @($resultados | Where-Object { $_.status -eq 'Erro' }).Count

    # Salvar JSON de resultado
    $resultadoJsonPath = Join-Path $DiretorioSaida 'correcoes-aplicadas.json'
    $resultadoJson = [pscustomobject]@{
        metadata = [pscustomobject]@{
            data_aplicacao        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            proposta_origem       = $PropostaFile
            total_diretorios      = $diretoriosParaAplicar.Count
            diretorios_corrigidos = $sucesso
            diretorios_falha      = $falha
            arquivos_afetados    = $totalArquivosAfetados
        }
        resultado = $resultados.ToArray()
    }

    Write-TextFileUtf8 -Path $resultadoJsonPath -Content ($resultadoJson | ConvertTo-Json -Depth 6)
    Write-Ok "Resultado salvo em: $resultadoJsonPath"

    # Gerar HTML de resultado
    $htmlPath = Join-Path $DiretorioSaida 'correcoes-aplicadas.html'
    $html = New-DropboxResultadoHtmlReport -DropboxPath $dropboxPath `
        -TotalAplicadas $totalArquivosAfetados -Sucesso ($totalArquivosAfetados - $falha) -Falha $falha -Resultados $resultados
    Write-TextFileUtf8 -Path $htmlPath -Content $html
    Write-Ok "Relatorio HTML gerado: $htmlPath"

    # Resumo
    Write-Host ''
    Write-Title "Resumo da aplicacao"
    Write-Ok "Diretorios corrigidos: $sucesso de $($diretoriosParaAplicar.Count)"
    Write-Info "Total de arquivos afetados: $totalArquivosAfetados"
    if ($falha -gt 0) {
        Write-Fail "Diretorios com falha: $falha"
    }
    Write-Info "Resultado JSON : $resultadoJsonPath"
    Write-Info "Resultado HTML : $htmlPath"
}
# Modo Relatorio: gerar relatório HTML
elseif ($Modo -eq 'Relatorio') {
    # Determinar qual arquivo usar
    $arquivoRelatorio = if (-not [string]::IsNullOrWhiteSpace($ResultadoFile)) { $ResultadoFile } else { $PropostaFile }
    $arquivoRelatorio = [System.IO.Path]::GetFullPath($arquivoRelatorio)

    if (-not (Test-Path -LiteralPath $arquivoRelatorio)) {
        Write-Fail "Arquivo nao encontrado: $arquivoRelatorio"
        exit 1
    }

    try {
        $dados = Get-Content -LiteralPath $arquivoRelatorio -Raw | ConvertFrom-Json
    }
    catch {
        Write-Fail "Nao foi possivel carregar o arquivo: $($_.Exception.Message)"
        exit 1
    }

    # Configurar diretório de saída
    if ([string]::IsNullOrWhiteSpace($DiretorioSaida)) {
        $DiretorioSaida = Join-Path (Split-Path -Parent $arquivoRelatorio) 'relatorio'
    }
    else {
        $DiretorioSaida = [System.IO.Path]::GetFullPath($DiretorioSaida)
    }

    if (-not (Test-Path -LiteralPath $DiretorioSaida -PathType Container)) {
        New-Item -ItemType Directory -Path $DiretorioSaida -Force | Out-Null
    }

    # Gerar HTML baseado no tipo de arquivo
    if ($dados.propostas) {
        # É uma proposta
        $dropboxPath = $dados.metadata.diagnostico_origem
        $totalPropostas = $dados.metadata.total_propostas
        $selecionadas = @($dados.propostas | Where-Object { $_.selecionado }).Count

        $htmlPath = Join-Path $DiretorioSaida 'correcoes-propostas.html'
        $html = New-DropboxPropostaHtmlReport -DropboxPath $dropboxPath `
            -TotalPropostas $totalPropostas -Selecionadas $selecionadas -Propostas $dados.propostas `
            -Diretorios @($dados.diretorios) -MetadataOriginal $dados.metadata -LimiteCaminho $LimiteCaminho
        Write-TextFileUtf8 -Path $htmlPath -Content $html
        Write-Ok "Relatório de propostas gerado: $htmlPath"
    }
    elseif ($dados.resultado) {
        # É um resultado
        $dropboxPath = $dados.metadata.proposta_origem
        $totalAplicadas = @($dados.resultado).Count
        $sucesso = @($dados.resultado | Where-Object { $_.status -eq 'Sucesso' }).Count
        $falha = @($dados.resultado | Where-Object { $_.status -ne 'Sucesso' }).Count

        $htmlPath = Join-Path $DiretorioSaida 'correcoes-aplicadas.html'
        $html = New-DropboxResultadoHtmlReport -DropboxPath $dropboxPath `
            -TotalAplicadas $totalAplicadas -Sucesso $sucesso -Falha $falha -Resultados $dados.resultado
        Write-TextFileUtf8 -Path $htmlPath -Content $html
        Write-Ok "Relatório de resultados gerado: $htmlPath"
    }
    else {
        Write-Fail "Formato de arquivo nao reconhecido. Esperado propostas ou resultado."
        exit 1
    }
}

Write-Host ''
Write-Info "Concluído."
