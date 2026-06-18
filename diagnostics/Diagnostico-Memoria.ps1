#Requires -Version 5.1
<#
.SYNOPSIS
    Identifica os maiores consumidores de memoria e gera relatorio para verificacao de legitimidade.

.DESCRIPTION
    Coleta os N processos com maior consumo de memoria e enriquece cada um com dados de publisher,
    assinatura digital, hash SHA256 e nivel de confianca do caminho. O relatorio HTML inclui links
    prontos para pesquisa no Google, ProcessLibrary e VirusTotal.

.FUNCIONALIDADES
    - Cria uma sessao padronizada em C:\WBA\Relatorios\Diagnostics\<timestamp>.
    - Ordena processos por Working Set, Private Bytes ou Mem. Paginada.
    - Coleta publisher e descricao via FileVersionInfo.
    - Verifica assinatura digital com Get-AuthenticodeSignature.
    - Calcula hash SHA256 para link direto ao VirusTotal.
    - Consulta owner e processo pai via Win32_Process (CIM).
    - Classifica cada processo como Confiavel, Verificar, Suspeito ou N/A.
    - Gera relatorio TXT sempre e HTML opcional com links de pesquisa.

.PARAMETER Top
    Quantidade de processos a analisar. Padrao: 10. Maximo: 50.

.PARAMETER Metrica
    Criterio de ordenacao: WorkingSet (padrao), PrivateBytes ou VirtualMemory.
    WorkingSet = RAM fisica em uso agora (pressao imediata).
    PrivateBytes = memoria exclusiva do processo (melhor para detectar leak).
    VirtualMemory = espaco de enderecamento reservado (util apenas para ranking; valores em TB sao normais).

.PARAMETER GerarHtml
    Gera relatorio HTML alem do TXT.

.PARAMETER AbrirRelatorio
    Abre o relatorio ao final da execucao.

.PARAMETER Todos
    Lista todos os processos sem limite de quantidade. Quando presente, -Top e ignorado.

.PARAMETER DiretorioSaida
    Raiz de relatorios escolhida pelo usuario. Quando omitido, usa ReportsRoot persistente do
    toolkit ou C:\WBA\Relatorios.

.EXAMPLE
    .\Diagnostico-Memoria.ps1

.EXAMPLE
    .\Diagnostico-Memoria.ps1 -Top 20 -Metrica PrivateBytes -GerarHtml -AbrirRelatorio

.EXAMPLE
    .\Diagnostico-Memoria.ps1 -Todos -GerarHtml -AbrirRelatorio

.EXAMPLE
    .\Diagnostico-Memoria.ps1 -GerarHtml -DiretorioSaida "D:\Relatorios\Teste"

.NOTES
    Autor  : WBA Windows Toolkit
    Versao : 0.1
    Requer : PowerShell 5.1+
    Escopo : Somente leitura. Nao altera processos, servicos ou configuracoes.

.LINK
    https://codeberg.org/wbaamaral/wba-windows-toolkit
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 50)]
    [int]$Top = 10,

    [ValidateSet('WorkingSet', 'PrivateBytes', 'VirtualMemory')]
    [string]$Metrica = 'WorkingSet',

    [switch]$Todos,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [string]$DiretorioSaida
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
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath        = $PSCommandPath
$ScriptDir         = $PSScriptRoot
$ToolkitRoot       = Split-Path -Parent $PSScriptRoot
$ToolkitModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $ToolkitModulePath -Force -ErrorAction Stop

$ScriptVersion     = 'v0.1'
$script:MemSession = $null

# WBA-DOCS: Category=Diagnostics; Related=Diagnostico-Driver-Grafico.ps1,Diagnostico-Reparo-HD100.ps1; Manual=Diagnostico de consumo de memoria

# ---------------------------------------------------------------------------
# Funcoes privadas
# ---------------------------------------------------------------------------

function Initialize-MemSession {
    [CmdletBinding()]
    param([string]$BasePath)

    $s = Initialize-ScriptSession -ModuleName 'Diagnostics' -BasePath $BasePath -ExecutionMode 'Diagnostico'
    $s | Add-Member -MemberType NoteProperty -Name 'TextReportPath'  -Value (Join-Path $s.Path     'diagnostico-memoria.txt')
    $s | Add-Member -MemberType NoteProperty -Name 'HtmlReportPath'  -Value (Join-Path $s.Path     'diagnostico-memoria.html')
    $s | Add-Member -MemberType NoteProperty -Name 'TranscriptPath'  -Value (Join-Path $s.LogsPath 'memoria-transcript.log')
    $s | Add-Member -MemberType NoteProperty -Name 'InternalLogPath' -Value (Join-Path $s.LogsPath 'memoria.log')
    return $s
}

function Write-MemLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $logPath = if ($script:MemSession) { $script:MemSession.InternalLogPath } else { $null }
    Write-ScriptLog -Message $Message -Level $Level -LogPath $logPath
}

function Write-MemSection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Section $Title
    Write-MemLog -Message $Title
}

function Format-MemSize {
    [CmdletBinding()]
    param([AllowNull()]$Bytes)
    if ($null -eq $Bytes) { return 'N/I' }
    try {
        $value = [long]$Bytes
        if ($value -le 0) { return '0 B' }
        return Format-FileSize -Bytes $value
    }
    catch { return 'N/I' }
}

function Get-ProcessTrustLevel {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return 'N/A' }

    $suspiciousBases = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP))        { $suspiciousBases.Add($env:TEMP) }
    if (-not [string]::IsNullOrWhiteSpace($env:TMP))         { $suspiciousBases.Add($env:TMP) }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $suspiciousBases.Add((Join-Path $env:USERPROFILE 'Downloads'))
        $suspiciousBases.Add((Join-Path $env:USERPROFILE 'Desktop'))
    }

    foreach ($base in $suspiciousBases) {
        if ($Path.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'Suspeito'
        }
    }

    $trustedBases = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot))    { $trustedBases.Add($env:SystemRoot) }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles))  { $trustedBases.Add($env:ProgramFiles) }
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not [string]::IsNullOrWhiteSpace($pf86))              { $trustedBases.Add($pf86) }

    foreach ($base in $trustedBases) {
        if ($Path.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'Confiavel'
        }
    }

    return 'Verificar'
}

function Get-ProcessMemoryData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Top,
        [Parameter(Mandatory = $true)][string]$Metrica,
        [switch]$Todos
    )

    $logMsg = if ($Todos) { "Coletando processos, metrica=$Metrica, todos" } else { "Coletando processos, metrica=$Metrica, top=$Top" }
    Write-MemLog -Message $logMsg

    $sortProperty = switch ($Metrica) {
        'PrivateBytes'  { 'PrivateMemorySize64' }
        'VirtualMemory' { 'VirtualMemorySize64' }
        default         { 'WorkingSet64' }
    }

    $processes = $null
    try {
        $sorted = Get-Process -ErrorAction Stop | Sort-Object -Property $sortProperty -Descending
        $processes = if ($Todos) { @($sorted) } else { @($sorted | Select-Object -First $Top) }
    }
    catch {
        Write-MemLog -Level 'ERROR' -Message "Falha ao listar processos: $($_.Exception.Message)"
        return @()
    }

    # Coletar Win32_Process de uma so vez para eficiencia
    $wmiMap = @{}
    try {
        $allWmi = @(Get-CimInstanceSafe -ClassName 'Win32_Process')
        foreach ($wp in $allWmi) {
            $wmiMap[[int]$wp.ProcessId] = $wp
        }
    }
    catch {
        Write-MemLog -Level 'WARN' -Message "Falha ao consultar Win32_Process: $($_.Exception.Message)"
    }

    $rank = 0
    $result = foreach ($proc in $processes) {
        $rank++

        $execPath    = ''
        $company     = 'N/I'
        $description = 'N/I'
        $fileVersion = 'N/I'
        $sigStatus   = 'N/A'
        $sha256      = 'N/A'
        $trustLevel  = 'N/A'

        # Tentar acessar .Path sem propagar excecao em processos protegidos
        try { $execPath = [string]$proc.Path } catch { $execPath = '' }

        if (-not [string]::IsNullOrWhiteSpace($execPath)) {
            $pathExists = $false
            try { $pathExists = Test-Path -LiteralPath $execPath -ErrorAction Stop } catch { }

            if ($pathExists) {
                try {
                    $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($execPath)
                    if ($fvi.CompanyName)     { $company     = $fvi.CompanyName }
                    if ($fvi.FileDescription) { $description = $fvi.FileDescription }
                    if ($fvi.FileVersion)     { $fileVersion = $fvi.FileVersion }
                }
                catch {
                    Write-MemLog -Level 'WARN' -Message "FileVersionInfo falhou para PID $($proc.Id): $($_.Exception.Message)"
                }

                try {
                    $sig = Get-AuthenticodeSignature -FilePath $execPath -ErrorAction Stop
                    $sigStatus = [string]$sig.Status
                }
                catch { $sigStatus = 'Erro' }

                try {
                    $hashResult = Get-FileHash -LiteralPath $execPath -Algorithm SHA256 -ErrorAction Stop
                    $sha256 = $hashResult.Hash
                }
                catch { $sha256 = 'N/A' }

                $trustLevel = Get-ProcessTrustLevel -Path $execPath
            }
        }

        # Owner e processo pai via CIM
        $owner      = 'N/I'
        $parentPid  = $null
        $parentName = 'N/I'
        $startTime  = 'N/I'

        if ($wmiMap.ContainsKey([int]$proc.Id)) {
            $wp = $wmiMap[[int]$proc.Id]

            try {
                $ownerResult = Invoke-CimMethod -InputObject $wp -MethodName 'GetOwner' -ErrorAction SilentlyContinue
                if ($null -ne $ownerResult) {
                    if ($ownerResult.Domain -and $ownerResult.User) {
                        $owner = "$($ownerResult.Domain)\$($ownerResult.User)"
                    }
                    elseif ($ownerResult.User) {
                        $owner = $ownerResult.User
                    }
                }
            }
            catch { }

            try {
                $parentPid = [int]$wp.ParentProcessId
                if ($wmiMap.ContainsKey($parentPid)) {
                    $parentName = [string]$wmiMap[$parentPid].Name
                }
                else {
                    $parentName = "PID $parentPid"
                }
            }
            catch { }

            try {
                if ($wp.CreationDate) {
                    $startTime = $wp.CreationDate.ToString('yyyy-MM-dd HH:mm:ss')
                }
            }
            catch { }
        }

        [pscustomobject]@{
            Rank          = $rank
            Nome          = $proc.ProcessName
            PID           = $proc.Id
            WorkingSet    = Format-MemSize -Bytes $proc.WorkingSet64
            PrivateBytes  = Format-MemSize -Bytes $proc.PrivateMemorySize64
            MemPaginada   = Format-MemSize -Bytes $proc.PagedMemorySize64
            MetricaValor  = Format-MemSize -Bytes $proc.$sortProperty
            WorkingSetRaw = $proc.WorkingSet64
            Publisher     = $company
            Descricao     = $description
            Versao        = $fileVersion
            Assinatura    = $sigStatus
            Nivel         = $trustLevel
            SHA256        = $sha256
            Owner         = $owner
            ParentPID     = $parentPid
            ParentNome    = $parentName
            Inicio        = $startTime
            Caminho       = $execPath
        }
    }

    return @($result)
}

function New-MemoryTextReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add('============================================================')
    $lines.Add(' DIAGNOSTICO DE CONSUMO DE MEMORIA')
    $lines.Add('============================================================')
    $lines.Add('')
    $lines.Add(('Computador : {0}' -f $Data.ComputerName))
    $lines.Add(('Usuario    : {0}' -f $Data.UserName))
    $lines.Add(('Execucao   : {0}' -f $Data.GeneratedAt))
    $lines.Add(('Metrica    : {0}' -f $Data.Metrica))
    $lines.Add(('Top        : {0}' -f $Data.Top))
    $lines.Add('')

    $totalRam     = ($Data.Processos | Measure-Object -Property WorkingSetRaw -Sum).Sum
    $naoConfiavel = @($Data.Processos | Where-Object { $_.Nivel -eq 'Suspeito' -or $_.Nivel -eq 'Verificar' }).Count
    $naoAssinado  = @($Data.Processos | Where-Object { $_.Assinatura -notin @('Valid', 'N/A') }).Count

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' GUIA DE METRICAS')
    $lines.Add('------------------------------------------------------------')
    $lines.Add('  Working Set   RAM fisica ocupada agora. Pressao imediata sobre o sistema.')
    $lines.Add('  Mem. Privada  Memoria exclusiva do processo (nao compartilhada). Melhor indicador')
    $lines.Add('                de leak: cresce sem cair = vazamento de memoria.')
    $lines.Add('  Mem. Paginada Memoria do processo no pool paginado. Complementar ao Working Set.')
    $lines.Add('  NOTA: Memoria Virtual (espaco de enderecamento reservado) foi omitida pois')
    $lines.Add('        valores em TB sao normais em apps 64-bit e nao refletem RAM fisica.')
    $lines.Add('')
    $lines.Add('------------------------------------------------------------')
    $lines.Add(' RESUMO')
    $lines.Add('------------------------------------------------------------')
    $lines.Add(('Processos analisados                   : {0}'  -f $Data.Processos.Count))
    $lines.Add(('RAM total Working Set dos analisados   : {0}'  -f (Format-MemSize -Bytes $totalRam)))
    $lines.Add(('Processos com nivel Suspeito/Verificar : {0}'  -f $naoConfiavel))
    $lines.Add(('Processos sem assinatura valida        : {0}'  -f $naoAssinado))
    $lines.Add('')

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' PROCESSOS')
    $lines.Add('------------------------------------------------------------')
    foreach ($p in $Data.Processos) {
        $lines.Add(('#' + $p.Rank + '  ' + $p.Nome + '  (PID ' + $p.PID + ')'))
        $lines.Add(('  Working Set   : {0}' -f $p.WorkingSet))
        $lines.Add(('  Mem. Privada  : {0}' -f $p.PrivateBytes))
        $lines.Add(('  Mem. Paginada : {0}' -f $p.MemPaginada))
        $lines.Add(('  Publisher     : {0}' -f $p.Publisher))
        $lines.Add(('  Descricao     : {0}' -f $p.Descricao))
        $lines.Add(('  Versao        : {0}' -f $p.Versao))
        $lines.Add(('  Assinatura    : {0}' -f $p.Assinatura))
        $lines.Add(('  Nivel         : {0}' -f $p.Nivel))
        $lines.Add(('  Owner         : {0}' -f $p.Owner))
        $lines.Add(('  Processo pai  : {0}' -f $p.ParentNome))
        $lines.Add(('  Inicio        : {0}' -f $p.Inicio))
        $lines.Add(('  Caminho       : {0}' -f $p.Caminho))
        $lines.Add(('  SHA256        : {0}' -f $p.SHA256))
        if ($p.SHA256 -ne 'N/A') {
            $lines.Add(('  VirusTotal    : https://www.virustotal.com/gui/file/{0}/detection' -f $p.SHA256))
        }
        $lines.Add('')
    }

    $lines.Add('------------------------------------------------------------')
    $lines.Add(' ARQUIVOS GERADOS')
    $lines.Add('------------------------------------------------------------')
    $lines.Add(('Relatorio TXT  : {0}' -f $Data.Output.TextReportPath))
    if ($Data.Output.HtmlReportPath) {
        $lines.Add(('Relatorio HTML : {0}' -f $Data.Output.HtmlReportPath))
    }
    $lines.Add(('Logs           : {0}' -f $Data.Output.LogsPath))

    return ($lines -join [Environment]::NewLine)
}

function Build-MemHtmlTableRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Processos)

    $rows = New-Object System.Collections.Generic.List[string]

    foreach ($p in $Processos) {
        $levelClass = switch ($p.Nivel) {
            'Confiavel' { 'nivel-ok' }
            'Suspeito'  { 'nivel-danger' }
            'Verificar' { 'nivel-warn' }
            default     { 'nivel-na' }
        }
        $sigClass = switch ($p.Assinatura) {
            'Valid' { 'sig-ok' }
            'N/A'   { 'sig-na' }
            default { 'sig-danger' }
        }

        $nomeSeguro   = ConvertTo-HtmlSafe $p.Nome
        $publisherSeg = ConvertTo-HtmlSafe $p.Publisher
        $descSeg      = ConvertTo-HtmlSafe $p.Descricao
        $ownerSeg     = ConvertTo-HtmlSafe $p.Owner
        $parentSeg    = ConvertTo-HtmlSafe $p.ParentNome
        $inicioSeg    = ConvertTo-HtmlSafe $p.Inicio
        $nivelSeg     = ConvertTo-HtmlSafe $p.Nivel
        $sigSeg       = ConvertTo-HtmlSafe $p.Assinatura
        $wsSeg        = ConvertTo-HtmlSafe $p.WorkingSet
        $pbSeg        = ConvertTo-HtmlSafe $p.PrivateBytes
        $mpSeg        = ConvertTo-HtmlSafe $p.MemPaginada
        $verSeg       = ConvertTo-HtmlSafe $p.Versao

        $pathExibido = if ($p.Caminho.Length -gt 65) {
            '...' + $p.Caminho.Substring($p.Caminho.Length - 62)
        }
        else { $p.Caminho }
        $pathTooltip = ConvertTo-HtmlSafe $p.Caminho
        $pathExibSeg = ConvertTo-HtmlSafe $pathExibido

        $nomeEnc    = [System.Uri]::EscapeDataString($p.Nome)
        $vtHref     = if ($p.SHA256 -ne 'N/A') {
            'https://www.virustotal.com/gui/file/' + $p.SHA256 + '/detection'
        }
        else { '#' }
        $vtLabel    = if ($p.SHA256 -ne 'N/A') { '[VT]' } else { '[VT?]' }
        $vtClass    = if ($p.SHA256 -ne 'N/A') { 'link-btn link-vt' } else { 'link-btn link-na' }

        $row  = '<tr>'
        $row += '<td class="rank">' + $p.Rank + '</td>'
        $row += '<td><b>' + $nomeSeguro + '</b><br><span class="muted small">PID ' + $p.PID + '</span></td>'
        $row += '<td>' + $wsSeg + '</td>'
        $row += '<td>' + $pbSeg + '</td>'
        $row += '<td>' + $mpSeg + '</td>'
        $row += '<td>' + $publisherSeg + '<br><span class="muted small">' + $descSeg + '</span><br><span class="muted small">v' + $verSeg + '</span></td>'
        $row += '<td><span class="badge ' + $sigClass + '">' + $sigSeg + '</span></td>'
        $row += '<td><span class="badge ' + $levelClass + '">' + $nivelSeg + '</span></td>'
        $row += '<td>'
        $row += '<span class="path-cell" title="' + $pathTooltip + '">' + $pathExibSeg + '</span>'
        $row += '<br><span class="muted small">Owner: ' + $ownerSeg + ' &nbsp;|&nbsp; Pai: ' + $parentSeg + '</span>'
        $row += '<br><span class="muted small">Inicio: ' + $inicioSeg + '</span>'
        $row += '</td>'
        $row += '<td class="nowrap">'
        $row += '<a href="https://www.google.com/search?q=' + $nomeEnc + '+process+windows+legitimate" target="_blank" class="link-btn" title="Pesquisar no Google">[G]</a> '
        $row += '<a href="https://www.processlibrary.com/en/process/?name=' + $nomeEnc + '.exe" target="_blank" class="link-btn" title="ProcessLibrary.com">[PL]</a> '
        $row += '<a href="' + $vtHref + '" target="_blank" class="' + $vtClass + '" title="VirusTotal — SHA256: ' + $p.SHA256 + '">' + $vtLabel + '</a>'
        $row += '</td>'
        $row += '</tr>'
        $rows.Add($row)
    }

    return ($rows -join [Environment]::NewLine)
}

function New-MemoryHtmlReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    $totalRam      = ($Data.Processos | Measure-Object -Property WorkingSetRaw -Sum).Sum
    $totalRamFmt   = Format-MemSize -Bytes $totalRam
    $naoConfiavel  = @($Data.Processos | Where-Object { $_.Nivel -eq 'Suspeito' -or $_.Nivel -eq 'Verificar' }).Count
    $naoAssinado   = @($Data.Processos | Where-Object { $_.Assinatura -notin @('Valid', 'N/A') }).Count

    $cardNaoConfClass   = if ($naoConfiavel -gt 0) { 'card-warn' }   else { 'card-ok' }
    $cardNaoAssinaClass = if ($naoAssinado  -gt 0) { 'card-danger' } else { 'card-ok' }

    $tableRowsHtml = Build-MemHtmlTableRows -Processos $Data.Processos

    $compNameSeg   = ConvertTo-HtmlSafe $Data.ComputerName
    $userNameSeg   = ConvertTo-HtmlSafe $Data.UserName
    $genAtSeg      = ConvertTo-HtmlSafe $Data.GeneratedAt
    $metricaSeg    = ConvertTo-HtmlSafe $Data.Metrica
    $txtPathSeg    = ConvertTo-HtmlSafe $Data.Output.TextReportPath
    $logsPathSeg   = ConvertTo-HtmlSafe $Data.Output.LogsPath

    $htmlLinhaHtml = ''
    if ($Data.Output.HtmlReportPath) {
        $htmlLinhaHtml = '<p><b>HTML:</b> <code>' + (ConvertTo-HtmlSafe $Data.Output.HtmlReportPath) + '</code></p>'
    }

    $html = @"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Diagnostico de Memoria - $compNameSeg</title>
<style>
@page { size: A4 landscape; margin: 12mm; }
* { box-sizing: border-box; }
body { font-family: Segoe UI,Arial,sans-serif; margin: 0; background: #f3f4f6; color: #1f2937; line-height: 1.45; font-size: 14px; }
.page { max-width: 1300px; margin: 24px auto; padding: 32px; background: #fff; box-shadow: 0 10px 15px rgba(0,0,0,.08); }
.toolbar { max-width: 1300px; margin: 24px auto 0; text-align: right; }
button { border: 0; border-radius: 4px; background: #2563eb; color: #fff; cursor: pointer; font: inherit; padding: 8px 14px; }
button:hover { background: #1d4ed8; }
h1 { margin-bottom: 4px; font-size: 22px; }
h2 { border-bottom: 1px solid #d1d5db; padding-bottom: 6px; margin-top: 28px; font-size: 16px; }
.muted { color: #6b7280; }
.small { font-size: 11px; }
.nowrap { white-space: nowrap; }
.rank { text-align: center; font-weight: 700; color: #374151; }
.path-cell { font-family: Consolas,monospace; font-size: 11px; word-break: break-all; }
.cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin: 16px 0; }
.card { border-radius: 8px; padding: 16px; border: 1px solid #e5e7eb; }
.card b { display: block; font-size: 11px; text-transform: uppercase; color: #6b7280; margin-bottom: 6px; }
.card-val { font-size: 26px; font-weight: 700; color: #1f2937; }
.card-ok     { background: #f0fdf4; border-color: #bbf7d0; }
.card-warn   { background: #fffbeb; border-color: #fde68a; }
.card-danger { background: #fef2f2; border-color: #fecaca; }
.badge { display: inline-block; border-radius: 999px; padding: 2px 10px; font-size: 12px; font-weight: 600; }
.nivel-ok     { background: #dcfce7; color: #166534; }
.nivel-warn   { background: #fef3c7; color: #92400e; }
.nivel-danger { background: #fee2e2; color: #991b1b; }
.nivel-na     { background: #f3f4f6; color: #6b7280; }
.sig-ok     { background: #dbeafe; color: #1e40af; }
.sig-danger { background: #fee2e2; color: #991b1b; }
.sig-na     { background: #f3f4f6; color: #6b7280; }
table { width: 100%; border-collapse: collapse; font-size: 12px; margin-top: 8px; }
th, td { border: 1px solid #e5e7eb; padding: 6px 8px; vertical-align: top; }
th { background: #f9fafb; text-align: left; font-size: 11px; text-transform: uppercase; color: #374151; }
tr:nth-child(even) { background: #fafafa; }
.link-btn { display: inline-block; font-size: 11px; font-weight: 600; border: 1px solid #d1d5db; border-radius: 4px; padding: 2px 5px; text-decoration: none; color: #374151; margin: 1px; }
.link-btn:hover { background: #e5e7eb; }
.link-vt { border-color: #bfdbfe; color: #1d4ed8; }
.link-vt:hover { background: #dbeafe; }
.link-na { color: #9ca3af; border-color: #e5e7eb; }
.info-box { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; }
code { font-family: Consolas,monospace; font-size: 12px; background: #f3f4f6; padding: 2px 5px; border-radius: 4px; }
@media print {
  body { background: #fff; }
  .toolbar { display: none; }
  .page { max-width: none; margin: 0; padding: 0; box-shadow: none; }
  * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
}
</style>
</head>
<body>
<div class="toolbar no-print"><button onclick="window.print()">Imprimir relatorio</button></div>
<div class="page">
<h1>Diagnostico de Consumo de Memoria</h1>
<p class="muted">Computador: <b>$compNameSeg</b> &nbsp;|&nbsp; Usuario: $userNameSeg &nbsp;|&nbsp; $genAtSeg &nbsp;|&nbsp; Metrica: $metricaSeg &nbsp;|&nbsp; Top $($Data.Top)</p>

<div class="cards">
  <div class="card">
    <b>RAM Total (Working Set dos analisados)</b>
    <span class="card-val">$totalRamFmt</span>
  </div>
  <div class="card $cardNaoConfClass">
    <b>Processos Suspeito / Verificar</b>
    <span class="card-val">$naoConfiavel</span>
  </div>
  <div class="card $cardNaoAssinaClass">
    <b>Sem assinatura valida</b>
    <span class="card-val">$naoAssinado</span>
  </div>
</div>

<h2>Processos &mdash; top $($Data.Top) por $metricaSeg</h2>
<div class="info-box" style="margin-bottom:12px;font-size:12px;">
  <b>Guia de metricas:</b>
  &nbsp;<b>Working Set</b> = RAM fisica ocupada agora (pressao imediata no sistema).
  &nbsp;<b>Mem. Privada</b> = memoria exclusiva do processo — melhor indicador de <em>leak</em> (cresce sem cair = vazamento).
  &nbsp;<b>Mem. Paginada</b> = pool paginado do processo, complementar ao Working Set.
  <span class="muted">&nbsp;Memoria Virtual omitida: espaco de enderecamento reservado pode ser dezenas de TB em apps 64-bit sem refletir RAM real.</span>
</div>
<p class="muted small">
  Links de pesquisa: <b>[G]</b> Google &nbsp;&nbsp;
  <b>[PL]</b> ProcessLibrary.com &nbsp;&nbsp;
  <b>[VT]</b> VirusTotal via hash SHA256 &nbsp;&mdash;&nbsp; todos abrem em nova aba.
</p>
<table>
<thead>
<tr>
  <th>#</th>
  <th>Processo / PID</th>
  <th>Working Set</th>
  <th>Mem. Privada</th>
  <th>Mem. Paginada</th>
  <th>Publisher / Descricao / Versao</th>
  <th>Assinatura</th>
  <th>Nivel</th>
  <th>Caminho / Owner / Pai / Inicio</th>
  <th>Pesquisar</th>
</tr>
</thead>
<tbody>
$tableRowsHtml
</tbody>
</table>

<h2>Arquivos gerados</h2>
<div class="info-box">
<p><b>TXT:</b> <code>$txtPathSeg</code></p>
$htmlLinhaHtml
<p><b>Logs:</b> <code>$logsPathSeg</code></p>
</div>

</div>
</body>
</html>
"@

    return $html
}

function Show-MemConsoleReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Data)

    Write-Title 'DIAGNOSTICO DE CONSUMO DE MEMORIA'
    Write-Info "Computador : $($Data.ComputerName)"
    Write-Info "Metrica    : $($Data.Metrica) | Top $($Data.Top)"

    Write-Section 'Resumo'
    $totalRam     = ($Data.Processos | Measure-Object -Property WorkingSetRaw -Sum).Sum
    $naoConfiavel = @($Data.Processos | Where-Object { $_.Nivel -eq 'Suspeito' -or $_.Nivel -eq 'Verificar' }).Count
    $naoAssinado  = @($Data.Processos | Where-Object { $_.Assinatura -notin @('Valid', 'N/A') }).Count

    Write-Info "RAM total Working Set analisada: $(Format-MemSize -Bytes $totalRam)"

    if ($naoConfiavel -gt 0) {
        Write-Warn "Processos com nivel Suspeito/Verificar: $naoConfiavel"
    }
    else {
        Write-Ok "Processos com nivel Suspeito/Verificar: 0"
    }

    if ($naoAssinado -gt 0) {
        Write-Warn "Processos sem assinatura valida: $naoAssinado"
    }
    else {
        Write-Ok "Processos sem assinatura valida: 0"
    }

    Write-Section 'Top processos'
    foreach ($p in $Data.Processos) {
        $nivel = $p.Nivel
        $line  = '#{0,-3} {1,-30} PID={2,-7} WS={3,-10} Nivel={4,-12} Assinatura={5}' -f `
            $p.Rank, $p.Nome, $p.PID, $p.WorkingSet, $nivel, $p.Assinatura
        switch ($nivel) {
            'Suspeito'  { Write-Fail $line }
            'Verificar' { Write-Warn $line }
            'Confiavel' { Write-Ok   $line }
            default     { Write-Info $line }
        }
    }

    Write-Section 'Arquivos gerados'
    Write-Ok "TXT  : $($Data.Output.TextReportPath)"
    if ($Data.Output.HtmlReportPath) {
        Write-Ok "HTML : $($Data.Output.HtmlReportPath)"
    }
    Write-Info "Logs : $($Data.Output.LogsPath)"
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if (-not (Test-IsAdministrator) -and [string]::IsNullOrWhiteSpace($DiretorioSaida)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        }
        else {
            "-$($kv.Key)"
            "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$script:MemSession = Initialize-MemSession -BasePath $DiretorioSaida
Start-Transcript -Path $script:MemSession.TranscriptPath -Force | Out-Null

try {
    Write-MemSection 'Preparacao'
    Write-MemLog -Message "Script: $ScriptName $ScriptVersion"
    Write-MemLog -Message "Destino: $($script:MemSession.Path)"
    Write-MemLog -Message "Metrica: $Metrica | Top: $Top"

    Write-MemSection 'Coletando dados de processos'
    $processos = @(Get-ProcessMemoryData -Top $Top -Metrica $Metrica -Todos:$Todos)

    $topLabel = if ($Todos) { 'Todos' } else { [string]$Top }
    $data = [pscustomobject]@{
        Tool          = 'WBA Windows Toolkit'
        Script        = $ScriptName
        ScriptVersion = $ScriptVersion
        GeneratedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ComputerName  = $env:COMPUTERNAME
        UserName      = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Top           = $topLabel
        Metrica       = $Metrica
        Processos     = @($processos)
        Output        = [pscustomobject]@{
            SessionPath    = $script:MemSession.Path
            LogsPath       = $script:MemSession.LogsPath
            TextReportPath = $script:MemSession.TextReportPath
            HtmlReportPath = if ($GerarHtml) { $script:MemSession.HtmlReportPath } else { $null }
        }
    }

    Write-MemSection 'Gerando relatorios'
    $textReport = New-MemoryTextReport -Data $data
    Write-TextFileUtf8 -Path $script:MemSession.TextReportPath -Content $textReport

    if ($GerarHtml) {
        $html = New-MemoryHtmlReport -Data $data
        Write-TextFileUtf8 -Path $script:MemSession.HtmlReportPath -Content $html
    }

    Show-MemConsoleReport -Data $data

    if ($AbrirRelatorio) {
        $target = if ($GerarHtml) { $script:MemSession.HtmlReportPath } else { $script:MemSession.TextReportPath }
        if (Test-Path -LiteralPath $target) {
            Start-Process -FilePath $target | Out-Null
        }
    }
}
catch {
    Write-MemLog -Level 'ERROR' -Message "Falha geral no diagnostico de memoria. $($_.Exception.Message)"
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
