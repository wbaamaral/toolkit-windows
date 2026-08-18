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
    
    if (-not (Test-Path -LiteralPath $Path)) { return }
    
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
    
    # Manter os primeiros 250 caracteres e adicionar hash se necessario
    if ($validChars.Length -gt ($MaxLenght - 10)) {
        $hash = Get-FileHash -Path ([System.IO.Path]::GetFileName($Name)) -Algorithm SHA256 | Select-Object -ExpandProperty Hash
        $hashShort = $hash.Substring(0, 8)
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
    
    try {
        # Obter o diretório do item
        $itemDir = Split-Path -Parent $Item.Caminho
        $originalName = $Item.Nome
        
        # Gerar um nome valido
        $newName = Get-ValidFileName -Name $originalName
        
        # Se o nome for o mesmo, não precisa corrigir
        if ($originalName -eq $newName) {
            Write-Info "Nome ja valido: $originalName"
            return $true
        }
        
        $newPath = Join-Path $itemDir $newName
        
        if ($Simular) {
            Write-Warn "[SIMULACAO] Renomeando para: $newPath"
        }
        else {
            # Criar backup
            Backup-Item -Path $Item.Caminho -BackupDir $BackupDir
            
            # Realizar o renomeio
            Rename-Item -LiteralPath $Item.Caminho -NewName $newName
            Write-Ok "Renomeado para: $newName"
        }
        
        return $true
    }
    catch {
        Write-Fail "Falha ao corrigir arquivo '$($Item.Nome)': $($_.Exception.Message)"
        return $false
    }
}

function Corrigir-MudancaLocalizacao {
    param(
        [pscustomobject]$Item,
        [string]$BackupDir,
        [string]$NewLocationDir
    )
    
    Write-Debug "Corrigindo arquivo por mudanca de localizacao: $($Item.Caminho)"
    
    try {
        if ($Simular) {
            Write-Warn "[SIMULACAO] Movendo para: $NewLocationDir"
        }
        else {
            # Criar backup
            Backup-Item -Path $Item.Caminho -BackupDir $BackupDir
            
            # Criar diretorio de destino se nao existir
            if (-not (Test-Path -LiteralPath $NewLocationDir -PathType Container)) {
                New-Item -ItemType Directory -Path $NewLocationDir -Force | Out-Null
            }
            
            # Copiar o arquivo para o novo local
            $destPath = Join-Path $NewLocationDir $Item.Nome
            Copy-Item -LiteralPath $Item.Caminho -Destination $destPath -Force
            
            # Remover o arquivo original
            Remove-Item -LiteralPath $Item.Caminho -Force
            
            Write-Ok "Movido para novo local: $destPath"
        }
        
        return $true
    }
    catch {
        Write-Fail "Falha ao mover arquivo '$($Item.Nome)': $($_.Exception.Message)"
        return $false
    }
}

# === Processamento principal ==============================================
Write-Title "Iniciando correcao em massa"

# Criar diretorio para backups
$backupDir = Join-Path $DiretorioSaida 'backups'
if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

$corrigidos = 0
$erros = 0

foreach ($arquivo in $jsonData.arquivos_problematicos) {
    Write-Host '' 
    Write-Info "Processando: $($arquivo.Nome)"
    
    if ($Correcao -eq 'Renomeacao') {
        # Correção por renomeação
        if (Corrigir-Rename -Item $arquivo -BackupDir $backupDir) {
            $corrigidos++
        }
        else {
            $erros++
        }
    }
    elseif ($Correcao -eq 'MudancaLocalizacao') {
        # Correção por mudança de localização
        $newLocation = Join-Path $DiretorioSaida 'arquivos_corrigidos'
        if (Corrigir-MudancaLocalizacao -Item $arquivo -BackupDir $backupDir -NewLocationDir $newLocation) {
            $corrigidos++
        }
        else {
            $erros++
        }
    }
}

# === Resumo ===============================================================
Write-Host ''
Write-Title "Resumo da correcao"
Write-Ok "Arquivos corrigidos: $corrigidos"
if ($erros -gt 0) {
    Write-Fail "Erros encontrados: $erros"
}
Write-Info "Log gerado em: $logFile"

# Salvar resumo
"Processo concluido em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $summaryLog -Encoding UTF8
"Arquivos corrigidos: $corrigidos" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
if ($erros -gt 0) {
    "Erros encontrados: $erros" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append
}
"Logs e backups salvos em: $DiretorioSaida" | Out-File -FilePath $summaryLog -Encoding UTF8 -Append

Write-Host ''
Write-Info "Proximo passo: verifique o log para confirmar as correcoes."
