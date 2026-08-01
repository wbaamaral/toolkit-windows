#Requires -Version 5.1
<#
.SYNOPSIS
    Detecta IPs associados a multiplos enderecos MAC em uma faixa de rede.

.DESCRIPTION
    Wrapper operacional da funcao Detect-DuplicateIp do modulo WbaToolkit.Networking.
    Expande a faixa informada (CIDR, intervalo ou IP unico), varre via ping ICMP
    assincrono, coleta os pares IP x MAC do cache ARP e gera relatorios em tres
    formatos (TXT, Markdown, HTML) na pasta de saida do toolkit.

    Nao exige privilegios administrativos: ping e leitura do cache ARP sao
    operacoes de usuario comum no Windows.

.PARAMETER Range
    Faixa de IP no formato CIDR ("192.168.1.0/24"), intervalo completo
    ("192.168.1.1-192.168.1.254"), intervalo compacto ("192.168.1.10-50")
    ou IP unico ("192.168.1.5").

.PARAMETER Interface
    Alias da interface de rede para filtrar a coleta ARP (ex.: "Ethernet0").
    Omita para coletar de todas as interfaces.

.PARAMETER OutputPath
    Raiz opcional dos relatorios. Se omitido, usa ReportsRoot persistente ou
    C:\WBA\Relatorios. A sessao sera criada em
    <Raiz>/detectar-ip-duplicado/<ddMMyyyy_HHmmss>/.

.PARAMETER TimeoutMs
    Tempo de espera por host em milissegundos. Default 500.

.PARAMETER Throttle
    Numero maximo de pings simultaneos. Default 50.

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\detectar-ip-duplicado.ps1 -Range '192.168.4.0/23'

.EXAMPLE
    .\detectar-ip-duplicado.ps1 -Range '192.168.1.10-50' -Interface 'Ethernet0'

.EXAMPLE
    .\detectar-ip-duplicado.ps1 -Range '192.168.4.0/23' -TimeoutMs 400 -Throttle 100

.NOTES
    Projeto: wba-toolkit
    Autor: wbaamaral
    Modulos requeridos:
      - WbaToolkit.Core (obrigatorio)
      - WbaToolkit.Networking (obrigatorio)

    ExecutionPolicy necessaria: RemoteSigned ou Bypass
      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force

    PowerShell 5.1 ou superior.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Range,

    [Parameter(Mandatory = $false)]
    [string]$Interface,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(50, 5000)]
    [int]$TimeoutMs = 500,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 500)]
    [int]$Throttle = 50,

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
    Write-Host "Deteccao de IP Duplicado — Duplicacao IP x MAC" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName -Range <faixa> [opcoes]"
    Write-Host ""
    Write-Host "  -Range '<faixa>'      Faixa de IP (CIDR, intervalo, compacto ou IP unico)."
    Write-Host "                        Ex.: '192.168.4.0/23' | '192.168.1.10-50' | '192.168.1.5'"
    Write-Host "  -Interface '<alias>'  Filtra coleta ARP por interface (ex.: 'Ethernet0')."
    Write-Host "  -OutputPath '<dir>'   Raiz opcional dos relatorios."
    Write-Host "                          Padrao: ReportsRoot ou C:\WBA\Relatorios"
    Write-Host "  -TimeoutMs <ms>       Tempo de espera por host. Default 500."
    Write-Host "  -Throttle <n>         Pings simultaneos (chunks). Default 50."
    Write-Host "  -Help                 Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName -Range '192.168.4.0/23'"
    Write-Host "  .\$ScriptName -Range '192.168.1.10-50' -Interface 'Ethernet0' -TimeoutMs 400"
    Write-Host "  .\$ScriptName -Range '192.168.4.0/23' -OutputPath 'C:\Temp\arp'"
    Write-Host ""
}

# Despacha -Help antes de qualquer verificacao de modulo ou elevacao (ADR 0021).
if ($Help) { Show-Help; exit 0 }

if ([string]::IsNullOrWhiteSpace($Range)) {
    Write-Host "[FALHA] Parametro -Range e obrigatorio." -ForegroundColor Red
    Write-Host "        Use -Help para ver exemplos." -ForegroundColor Yellow
    exit 1
}

# === Dependencias: adicionar modules/ ao PSModulePath (padrao-dependencias-modulos.md) ===
$moduleRoot = Join-Path $ToolkitRoot 'modules'
if ($env:PSModulePath -notlike "*$moduleRoot*") {
    $env:PSModulePath = "$moduleRoot;$env:PSModulePath"
}

$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$netModuleRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.Networking'

foreach ($mod in @($coreModuleRoot, $netModuleRoot)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        Write-Host "        Solucao: verifique o clone do repositorio em $ToolkitRoot" -ForegroundColor Yellow
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot, $netModuleRoot)) {
        foreach ($sub in @('Private', 'Public')) {
            $dir = Join-Path $moduleRoot $sub
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

# WBA-DOCS: Category=Networking; Related=testar-conectividade-internet.ps1; Manual=Deteccao de IP duplicado via ARP sweep

# === Cabecalho do operador ================================================
Write-Title "Deteccao de IP Duplicado — $Range"
Write-Info  "Varredura ARP com ping assincrono (timeout ${TimeoutMs}ms, throttle ${Throttle})."
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Info 'Relatorios: ReportsRoot persistente ou C:\WBA\Relatorios.'
}
else {
    Write-Info "Raiz de relatorios informada: $OutputPath"
}
Write-Host  ""

try {
    $results = Detect-DuplicateIp `
        -Range $Range `
        -Interface $Interface `
        -OutputPath $OutputPath `
        -TimeoutMs $TimeoutMs `
        -Throttle $Throttle `
        -ErrorAction Stop
}
catch {
    Write-Fail "Erro durante a varredura: $($_.Exception.Message)"
    exit 1
}

# === Resumo final ==========================================================
$totalFound = @($results).Count
$totalDup   = @($results | Where-Object Status -eq 'DUPLICADO').Count

Write-Host ""
Write-Ok "Varredura concluida: $totalFound IPs com ARP resolvido."
if ($totalDup -gt 0) {
    Write-Warn "$totalDup IP(s) com multiplos MACs (DUPLICADO):"
    $results | Where-Object Status -eq 'DUPLICADO' | ForEach-Object {
        Write-Host  "  $($_.IP):" -ForegroundColor Red
        foreach ($m in ($_.MACs -split ', ')) {
            Write-Host "    - $m" -ForegroundColor Red
        }
    }
} else {
    Write-Ok "Nenhuma duplicacao detectada."
}

if ($results.Count -gt 0 -and $null -ne $results[0].PSObject.Properties['ReportFiles']) {
    Write-Info "Relatorios gerados:"
    foreach ($p in $results[0].ReportFiles) {
        Write-Host "  $p" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Info "Proximo passo: abrir o arquivo .html para visualizar o relatorio completo."
