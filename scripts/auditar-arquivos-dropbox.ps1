#Requires -Version 5.1
<#
.SYNOPSIS
    Audita arquivos do Dropbox no Windows e classifica seu estado local.

.DESCRIPTION
    Wrapper operacional de Get-DropboxFileReport (WbaToolkit.Maintenance). Identifica
    arquivos do Dropbox usando atributos NTFS / Windows Cloud Files e classifica cada
    item.

    Estados reportados:
      - SomenteNuvem  : placeholder local; conteudo precisa ser recuperado da nuvem.
      - LocalENuvem   : conteudo esta materializado localmente.
      - SomenteLocal  : nao pode ser confirmado apenas por NTFS/Cloud Files.
      - Indeterminado : nao foi possivel classificar com seguranca.

    Quando -Path nao e informado, o script procura a pasta do Dropbox via
    Get-DropboxInstallation (%APPDATA%\Dropbox\info.json e
    %LOCALAPPDATA%\Dropbox\info.json). Se encontrar uma unica pasta valida, usa-a
    automaticamente. Se encontrar varias e estiver em modo interativo, pede a
    escolha. Se nao encontrar nenhuma e estiver em modo interativo, pede o caminho.

.PARAMETER Path
    Diretorio raiz do Dropbox a ser analisado. Se omitido, tenta autodetectar via
    Get-DropboxInstallation.

.PARAMETER Report
    Relatorio a exibir/gerar: All, CloudOnly, LocalAndCloud, LocalOnly, Indeterminate.

.PARAMETER Output
    Caminho opcional do arquivo de saida.

.PARAMETER Format
    Formato do arquivo de saida: CSV, JSON ou TXT. Padrao CSV.

.PARAMETER CsvDelimiter
    Delimitador do CSV. Deve conter exatamente um caractere. Padrao ';'.

.PARAMETER NonInteractive
    Impede qualquer pergunta interativa. O caminho do Dropbox continua sendo
    autodetectado; se isso nao for possivel ou for ambiguo, a execucao e encerrada
    e -Path deve ser informado explicitamente.

.PARAMETER Recurse
    Controla a analise recursiva de subdiretorios. Padrao $true.

.PARAMETER IncludeDirectories
    Inclui diretorios no relatorio, alem dos arquivos.

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\auditar-arquivos-dropbox.ps1

.EXAMPLE
    .\auditar-arquivos-dropbox.ps1 -Report CloudOnly

.EXAMPLE
    .\auditar-arquivos-dropbox.ps1 -Path 'D:\Dropbox' -Report LocalAndCloud

.EXAMPLE
    .\auditar-arquivos-dropbox.ps1 -NonInteractive -Path 'D:\Dropbox' -Report All -Output '.\dropbox-auditoria.csv'

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.Maintenance.

    IMPORTANTE:
    A classificacao "SomenteLocal" nao e autoritativa usando apenas os atributos do
    Windows. Para provar que um arquivo local ainda nao existe no Dropbox remoto e
    necessario reconciliar o filesystem com a API/estado remoto do Dropbox.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'CloudOnly', 'LocalAndCloud', 'LocalOnly', 'Indeterminate')]
    [string]$Report = 'All',

    [Parameter(Mandatory = $false)]
    [string]$Output,

    [Parameter(Mandatory = $false)]
    [ValidateSet('CSV', 'JSON', 'TXT')]
    [string]$Format = 'CSV',

    [Parameter(Mandatory = $false)]
    [ValidateLength(1, 1)]
    [string]$CsvDelimiter = ';',

    [Parameter(Mandatory = $false)]
    [switch]$NonInteractive,

    [Parameter(Mandatory = $false)]
    [bool]$Recurse = $true,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDirectories,

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
    Write-Host "Auditoria de Arquivos do Dropbox" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Path '<dir>'         Raiz do Dropbox. Padrao: autodetectar."
    Write-Host "  -Report '<filtro>'    All (padrao) | CloudOnly | LocalAndCloud | LocalOnly | Indeterminate"
    Write-Host "  -Output '<arquivo>'   Caminho do arquivo de saida."
    Write-Host "  -Format '<fmt>'       CSV (padrao) | JSON | TXT"
    Write-Host "  -CsvDelimiter '<c>'   Delimitador do CSV. Padrao ';'."
    Write-Host "  -NonInteractive       Nao faz perguntas; exige -Path se a deteccao for ambigua."
    Write-Host "  -Recurse <bool>       Analisa subdiretorios. Padrao true."
    Write-Host "  -IncludeDirectories   Inclui diretorios no relatorio."
    Write-Host "  -Help                 Esta ajuda."
    Write-Host ""
    Write-Host "Saida:"
    Write-Host "  Sem -Output : amostra de 50 itens no console."
    Write-Host "  Com -Output : lista completa no arquivo (CSV/JSON/TXT)."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Report CloudOnly"
    Write-Host "  .\$ScriptName -NonInteractive -Path 'D:\Dropbox' -Output '.\auditoria.csv'"
    Write-Host "  .\$ScriptName -Path 'D:\Dropbox' -Report All -Format JSON -Output '.\auditoria.json'"
    Write-Host ""
    Write-Host "Para diagnostico de saude completo, use diagnosticar-dropbox.ps1."
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
                Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
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

# WBA-DOCS: Category=Inventario; Related=diagnosticar-dropbox.ps1; Manual=Auditoria de arquivos do Dropbox via atributos NTFS/Cloud Files

function Resolve-DropboxAuditPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$NonInteractive
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $candidate = [Environment]::ExpandEnvironmentVariables($Path)
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            throw "Diretorio nao encontrado: $candidate"
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    Write-Info 'Localizando instalacao do Dropbox...'
    $installations = @(Get-DropboxInstallation)

    if ($installations.Count -eq 1) {
        return $installations[0].Caminho
    }

    if ($installations.Count -gt 1) {
        if ($NonInteractive) {
            $pathsText = ($installations | ForEach-Object { $_.Caminho }) -join '; '
            throw "Foram encontradas varias pastas Dropbox em modo nao interativo: $pathsText. Informe -Path explicitamente."
        }

        Write-Host ''
        Write-Host 'Foram encontradas varias pastas do Dropbox:'
        Write-Host ''
        for ($i = 0; $i -lt $installations.Count; $i++) {
            Write-Host ('[{0}] {1,-12} {2}' -f ($i + 1), $installations[$i].Conta, $installations[$i].Caminho)
        }
        Write-Host ''

        while ($true) {
            $selection = Read-UserInput -Question 'Selecione o numero da pasta Dropbox'
            $number = 0
            if ([int]::TryParse($selection, [ref]$number)) {
                $index = $number - 1
                if ($index -ge 0 -and $index -lt $installations.Count) {
                    return $installations[$index].Caminho
                }
            }
            Write-Warn 'Selecao invalida.'
        }
    }

    if ($NonInteractive) {
        throw "Nao foi possivel localizar automaticamente a pasta do Dropbox. Informe -Path explicitamente."
    }

    Write-Warn 'Nao foi possivel localizar automaticamente a pasta do Dropbox.'
    while ($true) {
        $manualPath = Read-UserInput -Question 'Informe manualmente o caminho da pasta Dropbox'
        $manualPath = [Environment]::ExpandEnvironmentVariables($manualPath.Trim('"'))
        if (Test-Path -LiteralPath $manualPath -PathType Container) {
            return (Resolve-Path -LiteralPath $manualPath).Path
        }
        Write-Warn "Diretorio nao encontrado: $manualPath"
    }
}

function Get-DropboxFilteredReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Results,

        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    switch ($ReportName) {
        'CloudOnly' {
            return @($Results | Where-Object { $_.Estado -eq 'SomenteNuvem' })
        }
        'LocalAndCloud' {
            return @($Results | Where-Object { $_.Estado -eq 'LocalENuvem' })
        }
        'LocalOnly' {
            Write-Warn 'Nao e possivel determinar de forma autoritativa arquivos "SomenteLocal" usando apenas atributos NTFS/Cloud Files.'
            return @($Results | Where-Object { $_.Estado -eq 'SomenteLocal' })
        }
        'Indeterminate' {
            return @($Results | Where-Object { $_.Estado -eq 'Indeterminado' })
        }
        default {
            return @($Results)
        }
    }
}

# === Cabecalho do operador ================================================
Write-Title "Auditoria de Arquivos do Dropbox"

try {
    $resolvedPath = Resolve-DropboxAuditPath -Path $Path -NonInteractive:$NonInteractive
}
catch {
    Write-Fail "Nao foi possivel resolver a pasta do Dropbox: $($_.Exception.Message)"
    exit 1
}

Write-Info "Pasta analisada: $resolvedPath"
Write-Info "Relatorio selecionado: $Report"
Write-Info 'Enumerando e classificando itens... (pastas corporativas grandes podem levar varios minutos)'
Write-Host ''

try {
    $results = @(Get-DropboxFileReport -Path $resolvedPath -Recurse $Recurse -IncludeDirectories:$IncludeDirectories)
}
catch {
    Write-Fail "Erro durante a auditoria: $($_.Exception.Message)"
    exit 1
}

$filteredResults = @(Get-DropboxFilteredReport -Results $results -ReportName $Report)

# === Resumo ================================================================
$summary = @(
    $results |
        Group-Object Estado |
        Sort-Object Name |
        Select-Object @{ Name = 'Estado'; Expression = { $_.Name } }, @{ Name = 'Quantidade'; Expression = { $_.Count } }
)

Write-Ok "Auditoria concluida: $($results.Count) item(ns) analisado(s)."
if ($summary.Count -gt 0) {
    $summary | Format-Table -AutoSize
}
Write-Info "Itens no relatorio '$Report': $($filteredResults.Count)"
Write-Host ''

# Sem -Output, uma pasta Dropbox corporativa real pode ter dezenas de milhares
# de itens -- imprimir tudo no console trava sessoes remotas/SSH. Mostra uma
# amostra e pede -Output para o operador ver a lista completa.
$consolePreviewLimit = 50
if ([string]::IsNullOrWhiteSpace($Output) -and $filteredResults.Count -gt 0) {
    $preview = @($filteredResults | Select-Object -First $consolePreviewLimit)
    $preview | Format-Table Estado, TamanhoMB, Pinned, Offline, Caminho -AutoSize

    if ($filteredResults.Count -gt $consolePreviewLimit) {
        Write-Info "Mostrando os primeiros $consolePreviewLimit de $($filteredResults.Count) itens. Use -Output para gravar a lista completa em arquivo."
    }
}

# === Saida ==================================================================
if (-not [string]::IsNullOrWhiteSpace($Output)) {
    $outputFullPath = [System.IO.Path]::GetFullPath($Output)

    switch ($Format) {
        'CSV' {
            $csvText = $filteredResults | ConvertTo-Csv -NoTypeInformation -Delimiter $CsvDelimiter
            Write-TextFileUtf8 -Path $outputFullPath -Content (($csvText -join "`r`n") + "`r`n")
        }
        'JSON' {
            Write-TextFileUtf8 -Path $outputFullPath -Content ($filteredResults | ConvertTo-Json -Depth 5)
        }
        'TXT' {
            $txtText = $filteredResults | Format-Table Estado, TamanhoMB, Pinned, Offline, Caminho -AutoSize | Out-String -Width 4096
            Write-TextFileUtf8 -Path $outputFullPath -Content $txtText
        }
    }

    Write-Info "Relatorio salvo em: $outputFullPath"
}

Write-Host ''
Write-Info 'Proximo passo: revisar os itens SomenteNuvem/Indeterminado antes de qualquer limpeza.'
