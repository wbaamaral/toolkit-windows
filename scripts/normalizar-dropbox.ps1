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
    5. Gera relatório detalhado de resultado (de → para)

    Este script e a FASE 2 do ciclo de normalizacao do Dropbox:

      diagnosticar-dropbox.ps1 -ExportarJson        (gera JSON)
                ↓
      normalizar-dropbox.ps1                         (TUI interativa)
                ↓
      correcoes-propostas.json + HTML                (validacao)
                ↓
      normalizar-dropbox.ps1 -Modo Aplicar           (aplica correcoes)
                ↓
      correcoes-aplicadas.json + HTML (de → para)    (resultado)

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

.PARAMETER NonInteractive
    Gera proposta sem TUI, com todos os itens selecionados.

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\normalizar-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'

    Modo TUI interativo — selecione/edite propostas antes de aplicar.

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
      correcoes-aplicadas.json : resultado detalhado (de → para)
      correcoes-aplicadas.html : relatorio visual do resultado
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
    Write-Host "  -NonInteractive              Gera proposta sem TUI."
    Write-Host "  -Help                        Esta ajuda."
    Write-Host ""
    Write-Host "Modos:"
    Write-Host "  TUI          Interface interativa para selecionar/editar propostas (padrao)."
    Write-Host "  Proposta     Gera proposta sem interacao (todos selecionados)."
    Write-Host "  Aplicar      Aplica proposta de um arquivo JSON."
    Write-Host "  Relatorio    Gera relatorio HTML de uma proposta ou resultado."
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

function Get-CorrecaoProposta {
    <#
    .SYNOPSIS
        Gera uma proposta de correção para um arquivo problemático.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Arquivo,
        [Parameter(Mandatory = $true)]
        [int]$Id
    )

    $proposta = [pscustomobject]@{
        id                   = $Id
        caminho_original     = [string]$Arquivo.Caminho
        caminho_proposto     = [string]$Arquivo.Caminho
        nome_original        = [string]$Arquivo.Nome
        nome_proposto        = [string]$Arquivo.Nome
        tipo_correcao        = 'Nenhuma'
        motivo               = ''
        selecionado          = $true
        editado_pelo_usuario = $false
    }

    # Verificar caracteres inválidos
    $invalidChars = '[<>:"/\\|?*]'
    if ($Arquivo.Nome -match $invalidChars) {
        $proposta.nome_proposto = Get-SafeFileName -Name $Arquivo.Nome
        $proposta.tipo_correcao = 'Renomeacao'
        $proposta.motivo = 'Caracteres inválidos no nome'
    }

    # Verificar comprimento do caminho
    if ([string]$Arquivo.Caminho.Length -gt 260) {
        $proposta.tipo_correcao = 'Renomeacao'
        $proposta.motivo = 'Caminho excede 260 caracteres'
    }

    # Verificar se é cópia em conflito
    if ($Arquivo.Nome -match 'Cópia em conflito') {
        $proposta.tipo_correcao = 'Renomeacao'
        $proposta.motivo = 'Conflito Dropbox'
    }

    # Atualizar caminho proposto se houver correção
    if ($proposta.tipo_correcao -ne 'Nenhuma') {
        $dir = Split-Path -Parent $proposta.caminho_original
        $proposta.caminho_proposto = Join-Path $dir $proposta.nome_proposto
    }

    return $proposta
}

function Show-TUI {
    <#
    .SYNOPSIS
        Exibe interface TUI para seleção e edição de propostas.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Propostas,
        [Parameter(Mandatory = $true)]
        [int]$PageSize,
        [Parameter(Mandatory = $true)]
        [string]$DropboxPath
    )

    $totalItems = $Propostas.Count
    $totalPages = [math]::Ceiling($totalItems / $PageSize)
    $currentPage = 1

    while ($true) {
        Clear-Host
        Write-Host "=== Normalização de Arquivos Dropbox ===" -ForegroundColor Cyan
        Write-Host "Pasta: $DropboxPath"
        Write-Host "Total: $totalItems arquivos problemáticos"
        Write-Host ""

        $startIdx = ($currentPage - 1) * $PageSize
        $endIdx = [math]::Min($startIdx + $PageSize - 1, $totalItems - 1)
        $pageItems = $Propostas[$startIdx..$endIdx]

        Write-Host "Página $currentPage/$totalPages (itens $($startIdx + 1)-$($endIdx + 1))" -ForegroundColor Yellow
        Write-Host ""
        Write-Host (" {0,-4} | {1,-6} | {2,-60} | {3,-25} | {4}" -f 'ID', 'Status', 'Caminho', 'Problema', 'Proposta')
        Write-Host ("-" * 4 + "-+-" + "-" * 6 + "-+-" + "-" * 60 + "-+-" + "-" * 25 + "-+-" + "-" * 30)

        foreach ($p in $pageItems) {
            $status = if ($p.selecionado) { '[✓]' } else { '[ ]' }
            $statusColor = if ($p.selecionado) { 'Green' } else { 'Red' }
            $caminho = if ($p.caminho_original.Length -gt 60) {
                '...' + $p.caminho_original.Substring($p.caminho_original.Length - 57)
            } else {
                $p.caminho_original
            }
            $motivo = if ($p.motivo.Length -gt 25) {
                $p.motivo.Substring(0, 22) + '...'
            } else {
                $p.motivo
            }
            $proposta = if ($p.tipo_correcao -eq 'Nenhuma') { '(sem alteração)' } else { $p.nome_proposto }

            Write-Host (" {0,-4} | " -f $p.id) -NoNewline
            Write-Host ("{0,-6}" -f $status) -ForegroundColor $statusColor -NoNewline
            Write-Host (" | {0,-60} | {1,-25} | {2}" -f $caminho, $motivo, $proposta)
        }

        Write-Host ""
        Write-Host "Comandos: [S]elecionar  [D]eselecionar  [T]odos  [E]ditar nome  [N]ext  [A]nterior  [G]erar proposta  [Q]uit" -ForegroundColor Cyan

        $cmd = Read-Host "Comando"
        $cmd = $cmd.Trim().ToUpper()

        switch -Regex ($cmd) {
            '^S\s+(\d+)$' {
                $id = [int]$Matches[1]
                $item = $Propostas | Where-Object { $_.id -eq $id }
                if ($item) {
                    $item.selecionado = $true
                    Write-Host "Item $id selecionado" -ForegroundColor Green
                }
            }
            '^D\s+(\d+)$' {
                $id = [int]$Matches[1]
                $item = $Propostas | Where-Object { $_.id -eq $id }
                if ($item) {
                    $item.selecionado = $false
                    Write-Host "Item $id deselecionado" -ForegroundColor Yellow
                }
            }
            '^T$' {
                $allSelected = ($Propostas | Where-Object { -not $_.selecionado }).Count -eq 0
                foreach ($p in $Propostas) { $p.selecionado = -not $allSelected }
                Write-Host "Todos $(if ($allSelected) { 'deselecionados' } else { 'selecionados' })" -ForegroundColor Yellow
            }
            '^E\s+(\d+)\s+(.+)$' {
                $id = [int]$Matches[1]
                $novoNome = $Matches[2].Trim()
                $item = $Propostas | Where-Object { $_.id -eq $id }
                if ($item) {
                    $item.nome_proposto = $novoNome
                    $item.editado_pelo_usuario = $true
                    $dir = Split-Path -Parent $item.caminho_original
                    $item.caminho_proposto = Join-Path $dir $novoNome
                    Write-Host "Nome do item $id atualizado para: $novoNome" -ForegroundColor Green
                }
            }
            '^N$' {
                if ($currentPage -lt $totalPages) { $currentPage++ }
            }
            '^A$' {
                if ($currentPage -gt 1) { $currentPage-- }
            }
            '^G$' {
                return $Propostas
            }
            '^Q$' {
                Write-Host "Operação cancelada pelo usuário." -ForegroundColor Yellow
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
    Write-Info "Total de arquivos problemáticos: $($jsonData.arquivos_problematicos.Count)"

    # Gerar propostas
    Write-Host ''
    Write-Title "Gerando propostas de correção"

    $propostas = New-Object System.Collections.Generic.List[pscustomobject]
    $id = 1
    foreach ($arquivo in $jsonData.arquivos_problematicos) {
        $nome = [string]$arquivo.Nome
        if ([string]::IsNullOrWhiteSpace($nome)) {
            $nome = Split-Path -Leaf ([string]$arquivo.Caminho)
        }
        $item = [pscustomobject]@{
            Caminho = [string]$arquivo.Caminho
            Nome    = $nome
        }

        $proposta = Get-CorrecaoProposta -Arquivo $item -Id $id
        [void]$propostas.Add($proposta)
        $id++
    }

    $totalPropostas = $propostas.Count
    $selecionadas = @($propostas | Where-Object { $_.selecionado }).Count

    Write-Ok "Propostas geradas: $totalPropostas"
    Write-Info "Selecionadas: $selecionadas"

    # TUI ou NonInteractive
    if ($Modo -eq 'TUI' -and -not $NonInteractive) {
        $propostas = Show-TUI -Propostas $propostas -PageSize $PageSize -DropboxPath $dropboxPath
        if ($null -eq $propostas) {
            Write-Host "Operação cancelada." -ForegroundColor Yellow
            exit 0
        }
        $selecionadas = @($propostas | Where-Object { $_.selecionado }).Count
    }

    # Configurar diretório de saída
    if ([string]::IsNullOrWhiteSpace($DiretorioSaida)) {
        $DiretorioSaida = Join-Path (Split-Path -Parent $InputFile) 'normalizacao'
    }
    else {
        $DiretorioSaida = [System.IO.Path]::GetFullPath($DiretorioSaida)
    }

    if (-not (Test-Path -LiteralPath $DiretorioSaida -PathType Container)) {
        New-Item -ItemType Directory -Path $DiretorioSaida -Force | Out-Null
    }

    # Salvar JSON de proposta
    $propostaJsonPath = Join-Path $DiretorioSaida 'correcoes-propostas.json'
    $propostaJson = [pscustomobject]@{
        metadata = [pscustomobject]@{
            data_geracao       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            versao_toolkit     = 'v1.0.0'
            diagnostico_origem = $InputFile
            total_propostas    = $totalPropostas
            selecionadas       = $selecionadas
        }
        propostas = @($propostas)
    }

    Write-TextFileUtf8 -Path $propostaJsonPath -Content ($propostaJson | ConvertTo-Json -Depth 6)
    Write-Ok "Proposta salva em: $propostaJsonPath"

    # Gerar HTML de proposta
    $htmlPath = Join-Path $DiretorioSaida 'correcoes-propostas.html'
    $html = New-DropboxPropostaHtmlReport -DropboxPath $dropboxPath `
        -TotalPropostas $totalPropostas -Selecionadas $selecionadas -Propostas $propostas
    Write-TextFileUtf8 -Path $htmlPath -Content $html
    Write-Ok "Relatório HTML gerado: $htmlPath"

    # Resumo
    Write-Host ''
    Write-Title "Resumo"
    Write-Info "Proposta JSON : $propostaJsonPath"
    Write-Info "Proposta HTML : $htmlPath"
    Write-Host ''
    Write-Info "Próximo passo: revise o HTML e aplique com -Modo Aplicar -PropostaFile '$propostaJsonPath'"
}

# Modo Aplicar: aplicar proposta
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

    if (-not ($propostaData -and $propostaData.propostas)) {
        Write-Fail "Estrutura do arquivo invalida. Nenhum dado de propostas encontrado."
        exit 1
    }

    $dropboxPath = $propostaData.metadata.diagnostico_origem
    $propostasParaAplicar = @($propostaData.propostas | Where-Object { $_.selecionado })

    Write-Info "Proposta carregada: $PropostaFile"
    Write-Info "Itens selecionados para aplicação: $($propostasParaAplicar.Count)"

    if ($propostasParaAplicar.Count -eq 0) {
        Write-Warn "Nenhum item selecionado para aplicação."
        exit 0
    }

    # Confirmar aplicação
    if (-not $NonInteractive) {
        $confirm = Read-YesNo -Question "Deseja aplicar $($propostasParaAplicar.Count) correções?" -DefaultYes $false
        if (-not $confirm) {
            Write-Host "Operação cancelada." -ForegroundColor Yellow
            exit 0
        }
    }

    # Configurar diretório de saída
    if ([string]::IsNullOrWhiteSpace($DiretorioSaida)) {
        $DiretorioSaida = Join-Path (Split-Path -Parent $PropostaFile) 'aplicacao'
    }
    else {
        $DiretorioSaida = [System.IO.Path]::GetFullPath($DiretorioSaida)
    }

    if (-not (Test-Path -LiteralPath $DiretorioSaida -PathType Container)) {
        New-Item -ItemType Directory -Path $DiretorioSaida -Force | Out-Null
    }

    $backupDir = Join-Path $DiretorioSaida 'backups'
    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    # Aplicar correções
    Write-Host ''
    Write-Title "Aplicando correções"

    $resultados = New-Object System.Collections.Generic.List[pscustomobject]
    $contador = 0

    foreach ($proposta in $propostasParaAplicar) {
        $contador++
        Write-Step "Processando item $($proposta.id) de $($propostasParaAplicar.Count)" ([math]::Round(($contador / $propostasParaAplicar.Count) * 100))

        $resultado = [pscustomobject]@{
            id        = $proposta.id
            de        = $proposta.caminho_original
            para      = $proposta.caminho_proposto
            status    = 'Erro'
            backup    = ''
            erro      = ''
            timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        try {
            # Backup
            if (-not (Backup-DropboxItem -Path $proposta.caminho_original -BackupDir $backupDir)) {
                throw "Falha ao criar backup de '$($proposta.caminho_original)'."
            }
            $resultado.backup = Join-Path $backupDir "$($proposta.nome_original).backup"

            # Aplicar correção
            if ($proposta.tipo_correcao -eq 'Renomeacao') {
                Rename-Item -LiteralPath $proposta.caminho_original -NewName $proposta.nome_proposto
            }

            $resultado.status = 'Sucesso'
            Write-Ok "Item $($proposta.id): $($proposta.nome_original) → $($proposta.nome_proposto)"
        }
        catch {
            $resultado.status = 'Erro'
            $resultado.erro = $_.Exception.Message
            Write-Fail "Item $($proposta.id): $($_.Exception.Message)"
        }

        [void]$resultados.Add($resultado)
    }

    $sucesso = @($resultados | Where-Object { $_.status -eq 'Sucesso' }).Count
    $falha = @($resultados | Where-Object { $_.status -eq 'Erro' }).Count

    # Salvar JSON de resultado
    $resultadoJsonPath = Join-Path $DiretorioSaida 'correcoes-aplicadas.json'
    $resultadoJson = [pscustomobject]@{
        metadata = [pscustomobject]@{
            data_aplicacao  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            proposta_origem = $PropostaFile
            total_aplicadas = $propostasParaAplicar.Count
            sucesso         = $sucesso
            falha           = $falha
        }
        resultado = @($resultados)
    }

    Write-TextFileUtf8 -Path $resultadoJsonPath -Content ($resultadoJson | ConvertTo-Json -Depth 6)
    Write-Ok "Resultado salvo em: $resultadoJsonPath"

    # Gerar HTML de resultado
    $htmlPath = Join-Path $DiretorioSaida 'correcoes-aplicadas.html'
    $html = New-DropboxResultadoHtmlReport -DropboxPath $dropboxPath `
        -TotalAplicadas $propostasParaAplicar.Count -Sucesso $sucesso -Falha $falha -Resultados $resultados
    Write-TextFileUtf8 -Path $htmlPath -Content $html
    Write-Ok "Relatório HTML gerado: $htmlPath"

    # Resumo
    Write-Host ''
    Write-Title "Resumo da aplicação"
    Write-Ok "Sucesso: $sucesso"
    if ($falha -gt 0) {
        Write-Fail "Falha: $falha"
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
        $selecionadas = $dados.metadata.selecionadas

        $htmlPath = Join-Path $DiretorioSaida 'correcoes-propostas.html'
        $html = New-DropboxPropostaHtmlReport -DropboxPath $dropboxPath `
            -TotalPropostas $totalPropostas -Selecionadas $selecionadas -Propostas $dados.propostas
        Write-TextFileUtf8 -Path $htmlPath -Content $html
        Write-Ok "Relatório de propostas gerado: $htmlPath"
    }
    elseif ($dados.resultado) {
        # É um resultado
        $dropboxPath = $dados.metadata.proposta_origem
        $totalAplicadas = $dados.metadata.total_aplicadas
        $sucesso = $dados.metadata.sucesso
        $falha = $dados.metadata.falha

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
