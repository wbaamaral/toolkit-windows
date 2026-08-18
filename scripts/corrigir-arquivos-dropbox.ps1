#Requires -Version 5.1
<#
.SYNOPSIS
    Corrige em massa arquivos problematicos do Dropbox identificados pelo toolkit.

.DESCRIPTION
    Ferramenta que processa relatorios de arquivos problematicos do Dropbox,
    com foco em problemas de tamanho de caminho acima de 260 caracteres.
    Oferece duas abordagens de correção: ajuste de nome ou mudança de localizacao.

.PARAMETER InputFile
    Arquivo JSON com a lista de arquivos problematicos gerado pelo diagnosticar-dropbox.ps1 -ExportarJson

.PARAMETER Correcao
    Tipo de correcao a ser aplicada: 'Renomeacao' ou 'MudancaLocalizacao'. Padrao: Renomeacao.

.PARAMETER Simular
    Executa apenas um dry-run para preview das alteracoes antes da aplicacao real.

.PARAMETER DiretorioSaida
    Diretorio onde serao salvos os logs e backups das operacoes.

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\corrigir-arquivos-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'

.EXAMPLE
    .\corrigir-arquivos-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json' -Correcao MudancaLocalizacao -Simular

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.Maintenance.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Renomeacao', 'MudancaLocalizacao')]
    [string]$Correcao = 'Renomeacao',

    [Parameter(Mandatory = $false)]
    [switch]$Simular,

    [Parameter(Mandatory = $false)]
    [string]$DiretorioSaida,

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
    Write-Host "Correcao em Massa de Arquivos Dropbox" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -InputFile '<arquivo>'      Arquivo JSON com a lista de arquivos problematicos."
    Write-Host "  -Correcao '<tipo>'           Renomeacao (padrao) ou MudancaLocalizacao."
    Write-Host "  -Simular                     Executa dry-run para preview das alteracoes."
    Write-Host "  -DiretorioSaida '<dir>'      Diretorio de saida para logs e backups."
    Write-Host "  -Help                        Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName -InputFile '.\diagnostico-dropbox.json'"
    Write-Host "  .\$ScriptName -InputFile '.\diagnostico-dropbox.json' -Correcao MudancaLocalizacao -Simular"
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

# === Verificacoes iniciais ==================================================
if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Fail "Arquivo de entrada nao encontrado: $InputFile"
    exit 1
}

$InputFile = [System.IO.Path]::GetFullPath($InputFile)
$InputFileDir = Split-Path -Parent $InputFile

# Diretorio de saida para logs e backups
if ([string]::IsNullOrWhiteSpace($DiretorioSaida)) {
    $DiretorioSaida = Join-Path $InputFileDir 'correcoes'
}
else {
    $DiretorioSaida = [System.IO.Path]::GetFullPath($DiretorioSaida)
}

# Criar diretorio de saida se nao existir
if (-not (Test-Path -LiteralPath $DiretorioSaida -PathType Container)) {
    New-Item -ItemType Directory -Path $DiretorioSaida -Force | Out-Null
}

# === Carregar dados de arquivos problematicos =============================
Write-Title "Carregando relatorio de arquivos problematicos"
try {
    $jsonData = Get-Content -LiteralPath $InputFile -Raw | ConvertFrom-Json
}
catch {
    Write-Fail "Nao foi possivel carregar o arquivo JSON: $($_.Exception.Message)"
    exit 1
}

# Validar estrutura do JSON
if (-not ($jsonData -and $jsonData.arquivos_problematicos)) {
    Write-Fail "Estrutura do arquivo invalida. Nenhum dado de arquivos problematicos encontrado."
    exit 1
}

Write-Ok "Arquivo carregado com sucesso: $($jsonData.metadata.caminho_analisado)"
Write-Info "Total de arquivos problemáticos: $($jsonData.arquivos_problematicos.Count)"
Write-Host ''

# === Preparacao do log ===================================================
$logFile = Join-Path $DiretorioSaida 'correcoes-dropbox.log'
$summaryLog = Join-Path $DiretorioSaida 'resumo-correcoes.txt'

# Iniciar log
"Correcao em massa de arquivos Dropbox - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logFile -Encoding UTF8
"Arquivo de entrada: $InputFile" | Out-File -FilePath $logFile -Encoding UTF8 -Append
"Tipo de correcao: $Correcao" | Out-File -FilePath $logFile -Encoding UTF8 -Append
"Modo: $(if ($Simular) { 'Dry-run (simulacao)' } else { 'Real' })" | Out-File -FilePath $logFile -Encoding UTF8 -Append
'' | Out-File -FilePath $logFile -Encoding UTF8 -Append

# === Funcoes de correcao ===================================================
function Backup-Item {
    param(
        [string]$Path,
        [string]$BackupDir
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    try {
        $fileName = Split-Path -Leaf $Path
        $backupPath = Join-Path $BackupDir "$fileName.backup"

        # Criar backup
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        Write-Debug "Criado backup: $backupPath"
        return $true
    }
    catch {
        Write-Warn "Nao foi possivel criar backup de '$Path': $($_.Exception.Message)"
        return $false
    }
}

function Get-ValidFileName {
    param(
        [string]$Name,
        [int]$MaxLenght = 259
    )

    # Remove caracteres invalidos
    $validChars = $Name -replace '[<>:"/\\|?*]', ''

    # Se o nome for vazio ou apenas espacos, dar um nome padrao
    if ([string]::IsNullOrWhiteSpace($validChars)) {
        $validChars = "arquivo_sem_nome"
    }

    # Remover espacos no final
    $validChars = $validChars.TrimEnd()

    # Manter os primeiros (MaxLenght - 10) caracteres e anexar hash curto do nome.
    # Get-FileHash exige caminho de arquivo existente; aqui o hash e calculado
    # diretamente sobre a string do nome via SHA256 (sem depender de arquivo).
    if ($validChars.Length -gt ($MaxLenght - 10)) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Name))
        $hashShort = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 8)
        $base = $validChars.Substring(0, ($MaxLenght - 10))
        $validChars = "$base-$hashShort"
    }

    return $validChars
}

function Corrigir-Rename {
    param(
        [pscustomobject]$Item,
        [string]$BackupDir
    )

    Write-Debug "Corrigindo arquivo por renomeacao: $($Item.Caminho)"

    $resultado = [pscustomobject]@{
        Acao     = 'Renomeacao'
        Status   = 'Erro'
        Caminho  = [string]$Item.Caminho
        NovoPath = $null
        Mensagem = ''
        Erro     = ''
    }

    try {
        # Obter o diretório do item
        $itemDir = Split-Path -Parent $Item.Caminho
        $originalName = $Item.Nome

        # Gerar um nome valido
        $newName = Get-ValidFileName -Name $originalName

        # Se o nome for o mesmo, não precisa corrigir
        if ($originalName -eq $newName) {
            $resultado.Status   = 'SemAlteracao'
            $resultado.NovoPath = $Item.Caminho
            $resultado.Mensagem = "Nome ja valido, nenhuma alteracao necessaria: $originalName"
            Write-Info $resultado.Mensagem
            return $resultado
        }

        $newPath = Join-Path $itemDir $newName

        if ($Simular) {
            $resultado.Status   = 'Simulado'
            $resultado.NovoPath = $newPath
            $resultado.Mensagem = "[SIMULACAO] Seria renomeado para: $newPath"
            Write-Warn $resultado.Mensagem
        }
        else {
            # Criar backup (seguranca: sem backup confiavel, abortar antes de alterar)
            if (-not (Backup-Item -Path $Item.Caminho -BackupDir $BackupDir)) {
                throw "Falha ao criar backup de '$($Item.Caminho)'; operacao abortada por seguranca."
            }

            # Realizar o renomeio
            Rename-Item -LiteralPath $Item.Caminho -NewName $newName
            $resultado.Status   = 'Corrigido'
            $resultado.NovoPath = $newPath
            $resultado.Mensagem = "Renomeado para: $newPath"
            Write-Ok $resultado.Mensagem
        }

        return $resultado
    }
    catch {
        $resultado.Status = 'Erro'
        $resultado.Erro   = $_.Exception.Message
        Write-Fail "Falha ao corrigir arquivo '$($Item.Nome)': $($_.Exception.Message)"
        return $resultado
    }
}

function Corrigir-MudancaLocalizacao {
    param(
        [pscustomobject]$Item,
        [string]$BackupDir,
        [string]$NewLocationDir
    )

    Write-Debug "Corrigindo arquivo por mudanca de localizacao: $($Item.Caminho)"

    $resultado = [pscustomobject]@{
        Acao     = 'MudancaLocalizacao'
        Status   = 'Erro'
        Caminho  = [string]$Item.Caminho
        NovoPath = $null
        Mensagem = ''
        Erro     = ''
    }

    try {
        $destPath = Join-Path $NewLocationDir $Item.Nome

        if ($Simular) {
            $resultado.Status   = 'Simulado'
            $resultado.NovoPath = $destPath
            $resultado.Mensagem = "[SIMULACAO] Seria movido para: $destPath"
            Write-Warn $resultado.Mensagem
        }
        else {
            # Criar backup (seguranca: sem backup confiavel, abortar antes de mover)
            if (-not (Backup-Item -Path $Item.Caminho -BackupDir $BackupDir)) {
                throw "Falha ao criar backup de '$($Item.Caminho)'; operacao abortada por seguranca."
            }

            # Criar diretorio de destino se nao existir
            if (-not (Test-Path -LiteralPath $NewLocationDir -PathType Container)) {
                New-Item -ItemType Directory -Path $NewLocationDir -Force | Out-Null
            }

            # Copiar o arquivo para o novo local
            Copy-Item -LiteralPath $Item.Caminho -Destination $destPath -Force

            # Remover o arquivo original
            Remove-Item -LiteralPath $Item.Caminho -Force

            $resultado.Status   = 'Corrigido'
            $resultado.NovoPath = $destPath
            $resultado.Mensagem = "Movido para novo local: $destPath"
            Write-Ok $resultado.Mensagem
        }

        return $resultado
    }
    catch {
        $resultado.Status = 'Erro'
        $resultado.Erro   = $_.Exception.Message
        Write-Fail "Falha ao mover arquivo '$($Item.Nome)': $($_.Exception.Message)"
        return $resultado
    }
}

# === Processamento principal ==============================================
Write-Title "Iniciando correcao em massa"

# Criar diretorio para backups
$backupDir = Join-Path $DiretorioSaida 'backups'
if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

$resultados = New-Object System.Collections.Generic.List[pscustomobject]

$newLocation = Join-Path $DiretorioSaida 'arquivos_corrigidos'

foreach ($arquivo in $jsonData.arquivos_problematicos) {
    Write-Host ''

    # Normaliza o item: tolera JSONs antigos sem o campo Nome, derivando-o do Caminho.
    $nome = [string]$arquivo.Nome
    if ([string]::IsNullOrWhiteSpace($nome)) {
        $nome = Split-Path -Leaf ([string]$arquivo.Caminho)
    }
    $item = [pscustomobject]@{
        Caminho = [string]$arquivo.Caminho
        Nome    = $nome
    }

    Write-Info "Processando: $nome"

    if ($Correcao -eq 'Renomeacao') {
        $resultado = Corrigir-Rename -Item $item -BackupDir $backupDir
    }
    elseif ($Correcao -eq 'MudancaLocalizacao') {
        $resultado = Corrigir-MudancaLocalizacao -Item $item -BackupDir $backupDir -NewLocationDir $newLocation
    }
    else {
        $resultado = $null
    }

    if ($null -ne $resultado) {
        [void]$resultados.Add($resultado)
    }
}

$corrigidos   = @($resultados | Where-Object { $_.Status -eq 'Corrigido' }).Count
$simulados    = @($resultados | Where-Object { $_.Status -eq 'Simulado' }).Count
$semAlteracao = @($resultados | Where-Object { $_.Status -eq 'SemAlteracao' }).Count
$erros        = @($resultados | Where-Object { $_.Status -eq 'Erro' }).Count

# === Saida em JSON (alteracoes, rollback e erros reprocessaveis) ==========
$alteracoesJsonPath = Join-Path $DiretorioSaida 'alteracoes.json'
$rollbackJsonPath = Join-Path $DiretorioSaida 'rollback.json'
$errosJsonPath = Join-Path $DiretorioSaida 'erros.json'
$simulacaoJsonPath = Join-Path $DiretorioSaida 'simulacao.json'

$alteracoesArray = @($resultados | Where-Object { $_.Status -eq 'Corrigido' } | ForEach-Object {
    [pscustomobject]@{
        Acao     = $_.Acao
        Caminho  = $_.Caminho
        NovoPath = $_.NovoPath
        Mensagem = $_.Mensagem
    }
})
$rollbackArray = @($resultados | Where-Object { $_.Status -eq 'Corrigido' } | ForEach-Object {
    [pscustomobject]@{
        Acao            = $_.Acao
        CaminhoOriginal = $_.Caminho
        CaminhoNovo     = $_.NovoPath
    }
})
$errosArray = @($resultados | Where-Object { $_.Status -eq 'Erro' } | ForEach-Object {
    [pscustomobject]@{
        Acao    = $_.Acao
        Caminho = $_.Caminho
        Erro    = $_.Erro
    }
})
$simulacaoArray = @($resultados | Where-Object { $_.Status -eq 'Simulado' } | ForEach-Object {
    [pscustomobject]@{
        Acao     = $_.Acao
        Caminho  = $_.Caminho
        NovoPath = $_.NovoPath
        Mensagem = $_.Mensagem
    }
})

$alteracoesJson = ConvertTo-Json -InputObject $alteracoesArray -Depth 5
$rollbackJson = ConvertTo-Json -InputObject $rollbackArray -Depth 5
$errosJson = ConvertTo-Json -InputObject $errosArray -Depth 5
$simulacaoJson = ConvertTo-Json -InputObject $simulacaoArray -Depth 5

Write-TextFileUtf8 -Path $alteracoesJsonPath -Content $alteracoesJson
Write-TextFileUtf8 -Path $rollbackJsonPath -Content $rollbackJson
Write-TextFileUtf8 -Path $errosJsonPath -Content $errosJson
if ($Simular) {
    Write-TextFileUtf8 -Path $simulacaoJsonPath -Content $simulacaoJson
}

# === Resumo ===============================================================
Write-Host ''
Write-Title "Resumo da correcao"
Write-Ok "Arquivos corrigidos: $corrigidos"
if ($simulados -gt 0) {
    Write-Warn "Alteracoes simuladas (dry-run): $simulados"
}
if ($semAlteracao -gt 0) {
    Write-Info "Itens sem alteracao necessaria: $semAlteracao"
}
if ($erros -gt 0) {
    Write-Fail "Erros encontrados: $erros"
}
Write-Info "Log gerado em: $logFile"

# Salvar resumo
"Processo concluido em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $summaryLog -Encoding UTF8
"Arquivos corrigidos: $corrigidos" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
if ($simulados -gt 0) {
    "Alteracoes simuladas (dry-run): $simulados" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
}
if ($semAlteracao -gt 0) {
    "Itens sem alteracao necessaria: $semAlteracao" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
}
if ($erros -gt 0) {
    "Erros encontrados: $erros" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
}
"Logs e backups salvos em: $DiretorioSaida" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
'' | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
"Alteracoes JSON : $alteracoesJsonPath" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
"Rollback JSON   : $rollbackJsonPath" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
"Erros JSON      : $errosJsonPath" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
if ($Simular) {
    "Simulacao JSON  : $simulacaoJsonPath" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
}

Write-Host ''
Write-Info "Alteracoes JSON : $alteracoesJsonPath"
Write-Info "Rollback JSON   : $rollbackJsonPath"
if ($erros -gt 0) {
    Write-Warn "Erros JSON      : $errosJsonPath"
}
if ($Simular) {
    Write-Info "Simulacao JSON  : $simulacaoJsonPath"
}

Write-Host ''
Write-Info "Proximo passo: verifique o log para confirmar as correcoes."
