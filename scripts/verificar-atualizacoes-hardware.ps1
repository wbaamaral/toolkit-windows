# =============================================================================
# [NAO VALIDADO] Script sem execucao real documentada em Windows.
# Nao recomendado para uso em producao ate validacao operacional.
# Registro: nao-validado/README.md
# =============================================================================
#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostico de atualizacoes de BIOS e drivers via Windows Update.

.DESCRIPTION
    Verifica o estado do BIOS (versao, data, fabricante, ferramenta oficial recomendada),
    inventaria os drivers instalados (versao, data, assinatura digital) e consulta o
    Windows Update para drivers disponiveis mas ainda nao instalados.

    O script e SOMENTE LEITURA: nao instala nada, nao altera o sistema.
    Atualizacoes de BIOS nunca sao aplicadas automaticamente — o script aponta a ferramenta
    oficial do fabricante para execucao manual controlada.

    A busca de drivers via Windows Update respeita politicas de GPO/WSUS: se o WU estiver
    bloqueado por politica corporativa, o script registra aviso e continua.

.PARAMETER GerarHtml
    Gera relatorio HTML alem do JSON.

.PARAMETER AbrirRelatorio
    Abre o relatorio HTML (ou JSON, se HTML nao foi gerado) ao final da execucao.

.PARAMETER Path
    Diretorio raiz de relatorios. Padrao: configuracao global ou C:\WBA\Relatorios.

.EXAMPLE
    .\verificar-atualizacoes-hardware.ps1

.EXAMPLE
    .\verificar-atualizacoes-hardware.ps1 -GerarHtml -AbrirRelatorio

.EXAMPLE
    .\verificar-atualizacoes-hardware.ps1 -GerarHtml -Path D:\Relatorios

.NOTES
    Autor  : WBA Windows Toolkit
    Versao : v1.0
    Requer : PowerShell 5.1+, elevacao de administrador
    Escopo : Diagnostico seguro e somente leitura. Nenhuma atualizacao e instalada.

.LINK
    https://codeberg.org/wbaamaral/wba-windows-toolkit
#>

[CmdletBinding()]
param(
    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Alias('DiretorioSaida')]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null } catch { }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
} else {
    Split-Path -Leaf $PSCommandPath
}

$ToolkitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Force -ErrorAction Stop

$ScriptVersion   = 'v1.0'
$script:HwSession = $null

# WBA-DOCS: Category=Diagnostics; Related=inventario-hardware-software.ps1,gerenciar-drivers.ps1; Manual=Diagnostico de atualizacoes de BIOS e drivers

function Write-HwLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $logPath = if ($script:HwSession) { $script:HwSession.InternalLogPath } else { $null }
    Write-ScriptLog -Message $Message -Level $Level -LogPath $logPath
}

function Write-HwSection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Section $Title
    Write-HwLog -Message $Title
}

function Initialize-HwSession {
    [CmdletBinding()]
    param([string]$BasePath)

    $session = Initialize-ScriptSession -ModuleName 'Diagnostics' -BasePath $BasePath -ExecutionMode 'Diagnostico'
    $session | Add-Member -MemberType NoteProperty -Name 'InternalLogPath' -Value (Join-Path $session.LogsPath 'hardware-updates.log')
    $session | Add-Member -MemberType NoteProperty -Name 'TranscriptPath'  -Value (Join-Path $session.LogsPath 'hardware-updates-transcript.log')
    $session | Add-Member -MemberType NoteProperty -Name 'HtmlReportPath'  -Value (Join-Path $session.Path    'hardware-updates.html')
    $session | Add-Member -MemberType NoteProperty -Name 'JsonReportPath'  -Value (Join-Path $session.Path    'hardware-updates.json')
    return $session
}

function ConvertFrom-HwCimDate {
    [CmdletBinding()]
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    try { return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value) }
    catch { try { return [datetime]$Value } catch { return $null } }
}

function Get-HwManufacturerTool {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Manufacturer)

    switch -Wildcard ($Manufacturer) {
        'Dell*'        { return 'Dell Command Update' }
        'HP*'          { return 'HP Support Assistant' }
        'Hewlett*'     { return 'HP Support Assistant' }
        'LENOVO*'      { return 'Lenovo System Update / Vantage' }
        'ASUSTeK*'     { return 'MyASUS / ASUS Update' }
        'ASUS*'        { return 'MyASUS / ASUS Update' }
        'MSI*'         { return 'MSI Center / Live Update' }
        'Micro-Star*'  { return 'MSI Center / Live Update' }
        'Gigabyte*'    { return '@BIOS (APP Center / Gigabyte Control Center)' }
        default        { return 'Site do fabricante da placa-mae' }
    }
}

function Get-BiosStatus {
    [CmdletBinding()]
    param()

    $bios = Get-CimInstanceSafe -ClassName 'Win32_BIOS' | Select-Object -First 1
    if ($null -eq $bios) { return $null }

    $biosDate  = ConvertFrom-HwCimDate -Value $bios.ReleaseDate
    $ageDays   = if ($null -ne $biosDate) { [int]((Get-Date) - $biosDate).TotalDays } else { $null }
    $ageYears  = if ($null -ne $ageDays)  { [math]::Round($ageDays / 365.25, 1) }    else { $null }
    $ferramenta = Get-HwManufacturerTool -Manufacturer ([string]$bios.Manufacturer)

    return [pscustomobject]@{
        Fabricante        = [string]$bios.Manufacturer
        SMBIOSBIOSVersion = [string]$bios.SMBIOSBIOSVersion
        BIOSVersion       = [string]($bios.BIOSVersion -join '; ')
        DataLancamento    = if ($null -ne $biosDate) { $biosDate.ToString('yyyy-MM-dd') } else { 'N/I' }
        IdadeDias         = $ageDays
        IdadeAnos         = $ageYears
        SerialNumber      = [string]$bios.SerialNumber
        FerramentaSugerida = $ferramenta
    }
}

function Get-DriverInventory {
    [CmdletBinding()]
    param()

    $drivers = @(Get-CimInstanceSafe -ClassName 'Win32_PnPSignedDriver')
    $result  = foreach ($d in $drivers) {
        if ([string]::IsNullOrWhiteSpace($d.DeviceName)) { continue }

        $driverDate = ConvertFrom-HwCimDate -Value $d.DriverDate
        $ageDays    = if ($null -ne $driverDate) { [int]((Get-Date) - $driverDate).TotalDays } else { $null }

        [pscustomobject]@{
            DeviceName    = [string]$d.DeviceName
            DeviceClass   = [string]$d.DeviceClass
            Manufacturer  = [string]$d.Manufacturer
            DriverVersion = [string]$d.DriverVersion
            DriverDate    = if ($null -ne $driverDate) { $driverDate.ToString('yyyy-MM-dd') } else { 'N/I' }
            IdadeDias     = $ageDays
            IsSigned      = [bool]$d.IsSigned
            Signer        = [string]$d.Signer
            InfName       = [string]$d.InfName
        }
    }

    return @($result | Sort-Object DeviceClass, DeviceName)
}

function Get-AvailableDriversWU {
    [CmdletBinding()]
    param()

    try {
        $wuSession = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher  = $wuSession.CreateUpdateSearcher()
        $result    = $searcher.Search("Type='Driver' AND IsInstalled=0")
        $updates   = @($result.Updates)

        $parsed = foreach ($upd in $updates) {
            $kb  = ($upd.KBArticleIDs | Select-Object -First 1)
            $desc = [string]$upd.Description
            [pscustomobject]@{
                Titulo     = [string]$upd.Title
                KB         = if ($kb) { "KB$kb" } else { 'N/I' }
                Severidade = [string]$upd.MsrcSeverity
                Descricao  = if ([string]::IsNullOrWhiteSpace($desc)) { '' } else {
                    $desc.Substring(0, [math]::Min(200, $desc.Length))
                }
            }
        }

        return @($parsed)
    }
    catch {
        Write-HwLog -Level 'WARN' -Message "Windows Update COM API indisponivel: $($_.Exception.Message)"
        Write-Warn "Windows Update nao acessivel (GPO/WSUS pode estar bloqueando)."
        return @()
    }
}

function ConvertTo-HwHtmlReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    $statusClass = if ($Data.StatusGeral -eq 'ATENCAO') { 'warn' } else { 'ok' }

    $biosRows = if ($Data.Bios) {
        $ageLabel = if ($null -ne $Data.Bios.IdadeAnos) { "$($Data.Bios.IdadeAnos) anos ($($Data.Bios.IdadeDias) dias)" } else { 'N/I' }
        $ageClass = if ($null -ne $Data.Bios.IdadeAnos -and [double]$Data.Bios.IdadeAnos -gt 2) { 'warn' } else { 'ok' }
        "<tr><td>Fabricante</td><td>$(ConvertTo-HtmlSafe $Data.Bios.Fabricante)</td></tr>
<tr><td>Versao</td><td>$(ConvertTo-HtmlSafe $Data.Bios.SMBIOSBIOSVersion)</td></tr>
<tr><td>Lancamento</td><td>$(ConvertTo-HtmlSafe $Data.Bios.DataLancamento)</td></tr>
<tr><td>Idade</td><td><span class=""badge $ageClass"">$ageLabel</span></td></tr>
<tr><td>Ferramenta sugerida</td><td><strong>$(ConvertTo-HtmlSafe $Data.Bios.FerramentaSugerida)</strong></td></tr>"
    } else {
        '<tr><td colspan="2" class="muted">BIOS nao disponivel.</td></tr>'
    }

    $driverRows = if ($Data.Drivers.Count -gt 0) {
        ($Data.Drivers | ForEach-Object {
            $rowClass = if (-not $_.IsSigned) { 'danger' } elseif ($null -ne $_.IdadeDias -and $_.IdadeDias -gt 730) { 'warn' } else { '' }
            '<tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td></tr>' -f `
                $rowClass,
                (ConvertTo-HtmlSafe $_.DeviceClass),
                (ConvertTo-HtmlSafe $_.DeviceName),
                (ConvertTo-HtmlSafe $_.DriverVersion),
                (ConvertTo-HtmlSafe $_.DriverDate),
                (ConvertTo-HtmlSafe $_.IsSigned),
                (ConvertTo-HtmlSafe $_.Manufacturer)
        }) -join "`n"
    } else {
        '<tr><td colspan="6" class="muted">Nenhum driver retornado.</td></tr>'
    }

    $wuRows = if ($Data.DriversWU.Count -gt 0) {
        ($Data.DriversWU | ForEach-Object {
            '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f `
                (ConvertTo-HtmlSafe $_.Titulo),
                (ConvertTo-HtmlSafe $_.KB),
                (ConvertTo-HtmlSafe $_.Severidade)
        }) -join "`n"
    } else {
        '<tr><td colspan="3" class="muted">Nenhum driver pendente encontrado no Windows Update.</td></tr>'
    }

    $ferramentaBios = if ($Data.Bios) { (ConvertTo-HtmlSafe $Data.Bios.FerramentaSugerida) } else { 'ferramenta do fabricante' }

    return @"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Atualizacoes de Hardware - $(ConvertTo-HtmlSafe $Data.ComputerName)</title>
<style>
* { box-sizing: border-box; }
body { font-family: Segoe UI, Arial, sans-serif; margin: 0; background: #f5f7fb; color: #1f2937; line-height: 1.45; }
.page { max-width: 1120px; margin: 24px auto; padding: 32px; background: #fff; box-shadow: 0 10px 15px rgba(0,0,0,.08); }
h1 { margin-bottom: 4px; }
h2 { border-bottom: 1px solid #d1d5db; padding-bottom: 6px; margin-top: 28px; }
.card { border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; margin: 12px 0; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; }
.metric { background: #f9fafb; border-radius: 8px; padding: 12px; border: 1px solid #e5e7eb; }
.metric b { display: block; color: #4b5563; font-size: 12px; text-transform: uppercase; margin-bottom: 6px; }
.badge { display: inline-block; border-radius: 999px; padding: 4px 10px; font-weight: 600; }
.ok { background: #dcfce7; color: #166534; }
.warn { background: #fef3c7; color: #92400e; }
.danger { background: #fee2e2; color: #991b1b; }
.muted { color: #6b7280; }
.alert { background: #fef3c7; border: 1px solid #fcd34d; padding: 12px 16px; border-radius: 6px; margin: 12px 0; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { border: 1px solid #e5e7eb; padding: 8px; vertical-align: top; }
th { background: #f3f4f6; text-align: left; }
tr.warn td { background: #fffbeb; }
tr.danger td { background: #fff1f2; }
</style>
</head>
<body>
<div class="page">
<h1>Verificar Atualizacoes de BIOS e Drivers</h1>
<p class="muted">Computador: <b>$(ConvertTo-HtmlSafe $Data.ComputerName)</b> | Execucao: $(ConvertTo-HtmlSafe $Data.GeneratedAt) | Script: $(ConvertTo-HtmlSafe $Data.ScriptVersion)</p>
<div class="card">
  <div class="grid">
    <div class="metric"><b>Status geral</b><span class="badge $statusClass">$(ConvertTo-HtmlSafe $Data.StatusGeral)</span></div>
    <div class="metric"><b>Total drivers</b>$($Data.Sumario.TotalDrivers)</div>
    <div class="metric"><b>Sem assinatura</b>$($Data.Sumario.SemAssinatura)</div>
    <div class="metric"><b>Antigos (&gt;2 anos)</b>$($Data.Sumario.Antigos)</div>
    <div class="metric"><b>Disponiveis (WU)</b>$($Data.Sumario.DisponivelWU)</div>
  </div>
</div>
<div class="alert">
<b>Somente leitura</b> — nenhuma atualizacao foi instalada.<br>
Para atualizar o BIOS, utilize <b>$ferramentaBios</b> e siga as instrucoes do fabricante.
Atualizacoes incorretas de BIOS podem tornar o hardware inutilizavel.
</div>

<h2>BIOS</h2>
<div class="card">
<table><tbody>
$biosRows
</tbody></table>
</div>

<h2>Drivers Instalados ($($Data.Drivers.Count))</h2>
<div class="card">
<table>
<thead><tr><th>Classe</th><th>Dispositivo</th><th>Versao</th><th>Data</th><th>Assinado</th><th>Fabricante</th></tr></thead>
<tbody>
$driverRows
</tbody>
</table>
</div>

<h2>Atualizacoes de Drivers via Windows Update ($($Data.DriversWU.Count))</h2>
<div class="card">
<table>
<thead><tr><th>Titulo</th><th>KB</th><th>Severidade</th></tr></thead>
<tbody>
$wuRows
</tbody>
</table>
</div>
</div>
</body>
</html>
"@
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if (-not (Test-IsAdministrator)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        } else {
            "-$($kv.Key)"
            "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$script:HwSession = Initialize-HwSession -BasePath $Path

Start-Transcript -Path $script:HwSession.TranscriptPath -Force | Out-Null

try {
    Write-Title "Verificar Atualizacoes de BIOS e Drivers — $ScriptVersion"
    Write-Info "Sessao : $($script:HwSession.Path)"
    Write-HwLog -Message "Inicio: $ScriptName $ScriptVersion"

    Write-HwSection 'BIOS'
    Write-Info "Consultando Win32_BIOS..."
    $biosStatus = Get-BiosStatus

    if ($null -eq $biosStatus) {
        Write-Fail "Nao foi possivel obter informacoes do BIOS."
        Write-HwLog -Level 'WARN' -Message 'Win32_BIOS retornou null'
    } else {
        Write-Info "Fabricante   : $($biosStatus.Fabricante)"
        Write-Info "Versao       : $($biosStatus.SMBIOSBIOSVersion)"
        Write-Info "Lancamento   : $($biosStatus.DataLancamento)"

        if ($null -ne $biosStatus.IdadeAnos) {
            $idadeMsg = "Idade do BIOS: $($biosStatus.IdadeAnos) anos ($($biosStatus.IdadeDias) dias)"
            if ($biosStatus.IdadeAnos -gt 2) {
                Write-Warn "$idadeMsg — considere verificar atualizacao"
            } else {
                Write-Ok "$idadeMsg"
            }
        }

        Write-Info "Ferramenta sugerida para atualizacao manual: $($biosStatus.FerramentaSugerida)"
        Write-Warn "Nunca atualize o BIOS automaticamente. Use a ferramenta oficial do fabricante e leia as instrucoes antes de executar."
        Write-HwLog -Message "BIOS: $($biosStatus.Fabricante) $($biosStatus.SMBIOSBIOSVersion) / $($biosStatus.DataLancamento)"
    }

    Write-HwSection 'Drivers instalados'
    Write-Info "Consultando Win32_PnPSignedDriver..."
    $driverInventory = @(Get-DriverInventory)
    Write-Info "Total de drivers: $($driverInventory.Count)"

    $naoAssinados = @($driverInventory | Where-Object { $_.IsSigned -eq $false })
    $antigos      = @($driverInventory | Where-Object { $null -ne $_.IdadeDias -and $_.IdadeDias -gt 730 })

    if ($naoAssinados.Count -gt 0) {
        Write-Warn "Drivers sem assinatura digital: $($naoAssinados.Count)"
        foreach ($d in $naoAssinados) {
            Write-Warn "  [Sem assinatura] $($d.DeviceClass): $($d.DeviceName)"
        }
    } else {
        Write-Ok "Todos os drivers possuem assinatura digital."
    }

    if ($antigos.Count -gt 0) {
        Write-Info "Drivers com mais de 2 anos: $($antigos.Count)"
        foreach ($d in (@($antigos) | Sort-Object IdadeDias -Descending | Select-Object -First 10)) {
            Write-Info "  [Antigo $($d.IdadeDias)d] $($d.DeviceClass): $($d.DeviceName) v$($d.DriverVersion)"
        }
    }
    Write-HwLog -Message "Drivers: total=$($driverInventory.Count) semAssinatura=$($naoAssinados.Count) antigos=$($antigos.Count)"

    Write-HwSection 'Atualizacoes de drivers via Windows Update'
    Write-Info "Consultando Windows Update COM API (somente leitura)..."
    $wuDrivers = @(Get-AvailableDriversWU)

    if ($wuDrivers.Count -eq 0) {
        Write-Ok "Nenhum driver pendente encontrado no Windows Update."
    } else {
        Write-Warn "Drivers disponiveis para instalar via WU: $($wuDrivers.Count)"
        foreach ($upd in $wuDrivers) {
            Write-Info "  [$($upd.KB)] $($upd.Titulo)"
        }
    }
    Write-HwLog -Message "Windows Update: $($wuDrivers.Count) drivers disponiveis"

    Write-HwSection 'Resumo'
    $statusGeral = 'OK'
    if ($naoAssinados.Count -gt 0 -or $wuDrivers.Count -gt 0) { $statusGeral = 'ATENCAO' }
    if ($null -ne $biosStatus -and $null -ne $biosStatus.IdadeAnos -and $biosStatus.IdadeAnos -gt 2) { $statusGeral = 'ATENCAO' }

    switch ($statusGeral) {
        'ATENCAO' { Write-Warn "Status geral     : ATENCAO" }
        default   { Write-Ok   "Status geral     : OK" }
    }
    Write-Info "Drivers sem assinatura : $($naoAssinados.Count)"
    Write-Info "Drivers antigos (>2a)  : $($antigos.Count)"
    Write-Info "Drivers pendentes (WU) : $($wuDrivers.Count)"

    $report = [pscustomobject]@{
        Tool          = 'WBA Windows Toolkit'
        Script        = $ScriptName
        ScriptVersion = $ScriptVersion
        GeneratedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ComputerName  = $env:COMPUTERNAME
        StatusGeral   = $statusGeral
        Bios          = $biosStatus
        Drivers       = @($driverInventory)
        DriversWU     = @($wuDrivers)
        Sumario       = [pscustomobject]@{
            TotalDrivers  = $driverInventory.Count
            SemAssinatura = $naoAssinados.Count
            Antigos       = $antigos.Count
            DisponivelWU  = $wuDrivers.Count
        }
    }

    Write-TextFileUtf8 -Path $script:HwSession.JsonReportPath -Content ($report | ConvertTo-Json -Depth 6)
    Write-Ok "JSON: $($script:HwSession.JsonReportPath)"

    if ($GerarHtml) {
        $html = ConvertTo-HwHtmlReport -Data $report
        Write-TextFileUtf8 -Path $script:HwSession.HtmlReportPath -Content $html
        Write-Ok "HTML: $($script:HwSession.HtmlReportPath)"
    }

    if ($AbrirRelatorio) {
        $target = if ($GerarHtml) { $script:HwSession.HtmlReportPath } else { $script:HwSession.JsonReportPath }
        if (Test-Path -LiteralPath $target) {
            Start-Process -FilePath $target | Out-Null
        }
    }
}
catch {
    Write-HwLog -Level 'ERROR' -Message "Falha geral: $($_.Exception.Message)"
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
