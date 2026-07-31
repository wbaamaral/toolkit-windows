#Requires -Version 5.1
<#
.SYNOPSIS
    Analisa o uso de espaco em disco, identifica potencial de limpeza e gera
    relatorio com Top 20 pastas e Top 10 arquivos por tamanho.

.DESCRIPTION
    Varre os volumes locais do computador usando System.IO de alto desempenho,
    calcula o tamanho total de cada pasta (incluindo subpastas), detecta arquivos
    e pastas ocultos, estima categorias de espaco desperdicado e gera:

    - Exibicao no console no estilo Baobab/Disk Usage Analyzer com barras ASCII.
    - Relatorio HTML com Top 20 pastas, Top 10 arquivos e estimativa de limpeza.

    NENHUMA acao destrutiva e realizada. O script e estritamente de leitura.

    Funcionalidades:
    - Varre todos os volumes locais fixos (ou drive especificado com -Drive).
    - Ignora pontos de reparse (juncoes, links simbolicos) para evitar loops.
    - Marca pastas e arquivos ocultos no relatorio.
    - Detecta categorias de espaco desperdicado: temp, cache, dumps, logs antigos,
      Windows.old, hiberfil.sys, lixeira, cache de browsers, WinSxS.
    - Top 20 pastas por tamanho total com barra visual proporcional.
    - Top 10 arquivos por tamanho individual.
    - Relatorio HTML salvo na pasta padronizada do toolkit com conversao opcional para PDF.
    - Log completo da execucao em logs da sessao.

.PARAMETER Drive
    Volume(s) a varrer (ex: C). Quando omitido, varre todos os volumes locais fixos.

.PARAMETER Path
    Raiz de relatorios escolhida pelo usuario (alias: -DiretorioSaida). Quando omitido,
    usa ReportsRoot persistente do toolkit ou C:\WBA\Relatorios. O script cria
    automaticamente Utilities\<timestamp>.

.PARAMETER NaoPDF
    Gera apenas o relatorio HTML, sem tentar converter para PDF.

.PARAMETER Silent
    Suprime a barra de progresso da varredura no console.

.PARAMETER Help
    Exibe a ajuda resumida do script.

.PARAMETER Version
    Exibe a versao do script.

.PARAMETER MaxDepth
    Limita a profundidade da varredura (0 = ilimitado, padrao). Use um valor pequeno
    (ex.: 2 ou 3) para um panorama rapido das maiores pastas de alto nivel; nesse caso
    a varredura e parcial (subpastas alem do limite nao sao somadas).

.EXAMPLE
    .\analisar-espaco-disco.ps1

    Varre todos os volumes locais fixos e gera HTML + PDF na pasta padronizada de relatorios.

.EXAMPLE
    .\analisar-espaco-disco.ps1 -Drive C -MaxDepth 3

    Panorama rapido (parcial) ate 3 niveis de profundidade no volume C:.

.EXAMPLE
    .\analisar-espaco-disco.ps1 -Drive C

    Varre apenas o volume C:.

.EXAMPLE
    .\analisar-espaco-disco.ps1 -DiretorioSaida "D:\Relatorios"

    Salva os relatorios em D:\Relatorios (criada automaticamente se nao existir).

.EXAMPLE
    .\analisar-espaco-disco.ps1 -NaoPDF

    Gera apenas o HTML, sem conversao para PDF.

.EXAMPLE
    .\analisar-espaco-disco.ps1 -Drive C,D -DiretorioSaida D:\Relatorios -NaoPDF

    Varre C: e D:, grava em D:\Relatorios e nao gera PDF.

.NOTES
    Requer privilegios de Administrador para acessar pastas protegidas do sistema.
    O tempo de varredura varia com o tamanho do disco (tipicamente 1-5 min para C:).
    Testado conceitualmente para Windows 10 Pro (21H2+) e Windows 11 Pro.

.LINK
    https://codeberg.org/wbaamaral/wba-windows-toolkit
#>
param (
    [switch]$Help,
    [switch]$Version,
    [string[]]$Drive,
    [Alias('DiretorioSaida')]
    [string]$Path,
    [switch]$NaoPDF,
    [switch]$Silent,
    [int]$MaxDepth = 0
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null } catch { }


$ToolkitRoot    = Split-Path -Parent $PSScriptRoot
$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'

if (-not (Test-Path -LiteralPath $coreModuleRoot)) {
    throw "Modulo nao encontrado: $coreModuleRoot"
}

try {
    foreach ($sub in @('Private', 'Public')) {
        $dir = Join-Path $coreModuleRoot $sub
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
        }
    }
}
catch {
    throw "Nao foi possivel carregar WbaToolkit.Core: $($_.Exception.Message)"
}

# WBA-DOCS: Category=Utilities; Manual=Analise de uso de espaco em disco com Top pastas/arquivos e estimativa de limpeza (somente leitura)

$ScriptVersion = 'v1.0.0'
$ScriptName    = $MyInvocation.MyCommand.Name
$ScriptPath    = $PSCommandPath
$ScriptDir     = $PSScriptRoot
$ReportSession = $null
$LogDir        = $null
$LogFile       = $null

# ---------------------------------------------------------------------------
# Utilitarios
# ---------------------------------------------------------------------------

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Analise de Espaco em Disco — $script:ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$script:ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Drive '<letra>'   Volume a varrer (ex: C). Padrao: todos os locais fixos."
    Write-Host "  -DiretorioSaida '<dir>' Raiz de relatorios. Padrao: ReportsRoot persistente ou C:\WBA\Relatorios"
    Write-Host "  -NaoPDF            Gera apenas HTML sem converter para PDF."
    Write-Host "  -MaxDepth <n>      Limita a profundidade (0=ilimitado). Ex: 3 = panorama rapido parcial."
    Write-Host "  -Silent            Sem saida de progresso no console."
    Write-Host "  -Help              Esta ajuda."
    Write-Host "  -Version           Versao do script."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$script:ScriptName"
    Write-Host "  .\$script:ScriptName -Drive C"
    Write-Host "  .\$script:ScriptName -Drive C,D -DiretorioSaida D:\Relatorios -NaoPDF"
    Write-Host ""
}

function Get-AsciiBar {
    [CmdletBinding()]
    param([double]$Pct, [int]$Width = 25)
    $filled = [int][Math]::Round($Pct / 100 * $Width)
    $empty  = $Width - $filled
    return ('█' * $filled) + ('░' * $empty)
}

function Get-BarColor {
    [CmdletBinding()]
    param([double]$Pct)
    if ($Pct -ge 85) { return 'Red'    }
    if ($Pct -ge 65) { return 'Yellow' }
    return 'Green'
}

# ---------------------------------------------------------------------------
# Varredura do disco
# ---------------------------------------------------------------------------

function Invoke-DiskScan {
    [CmdletBinding()]
    param([string]$RootPath, [switch]$Quiet, [int]$MaxDepth = 0)

    $folderLocalSizes = [System.Collections.Generic.Dictionary[string,long]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $folderAttribs = [System.Collections.Generic.Dictionary[string,int]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $topFiles = New-Object 'System.Collections.Generic.List[PSCustomObject]'
    $topFilesMax = 200
    $topFilesMin = [long]::MaxValue   # menor tamanho atual no Top-N (mantido incrementalmente)

    $stack      = New-Object 'System.Collections.Generic.Stack[string]'
    $depthStack = New-Object 'System.Collections.Generic.Stack[int]'
    $stack.Push($RootPath)
    $depthStack.Push(0)
    $scannedDirs  = [long]0
    $scannedFiles = [long]0
    $scannedBytes = [long]0
    $lastProgress = [DateTime]::Now

    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $depth = $depthStack.Pop()
        $localSize = [long]0
        $attrib = 0
        $di = $null

        try {
            $di = [System.IO.DirectoryInfo]::new($dir)
            $attrib = [int]$di.Attributes
            # Ignora reparse points (juncoes, symlinks) para evitar loops/dupla contagem
            if ($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $folderLocalSizes[$dir] = [long]0
                $folderAttribs[$dir] = $attrib
                continue
            }
        } catch { $di = $null }

        if ($null -ne $di) {
            # EnumerateFiles devolve FileInfo ja preenchido pela enumeracao do diretorio
            # (sem New-Object e sem stat extra por arquivo) — bem mais rapido que GetFiles + FileInfo.
            try {
                foreach ($fi in $di.EnumerateFiles()) {
                    try {
                        $sz = $fi.Length
                        $localSize += $sz
                        $scannedFiles++

                        # Top-N por tamanho com minimo incremental (sem Measure-Object por arquivo).
                        if ($topFiles.Count -lt $topFilesMax) {
                            $topFiles.Add([PSCustomObject]@{
                                Path = $fi.FullName; Name = $fi.Name; Dir = $dir
                                Ext = $fi.Extension.ToLower(); Size = $sz
                                IsHidden = ($fi.Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0
                                IsSystem = ($fi.Attributes -band [System.IO.FileAttributes]::System) -ne 0
                            })
                            if ($sz -lt $topFilesMin) { $topFilesMin = $sz }
                        }
                        elseif ($sz -gt $topFilesMin) {
                            $topFiles.Add([PSCustomObject]@{
                                Path = $fi.FullName; Name = $fi.Name; Dir = $dir
                                Ext = $fi.Extension.ToLower(); Size = $sz
                                IsHidden = ($fi.Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0
                                IsSystem = ($fi.Attributes -band [System.IO.FileAttributes]::System) -ne 0
                            })
                            if ($topFiles.Count -gt $topFilesMax * 2) {
                                $sorted = $topFiles | Sort-Object Size -Descending | Select-Object -First $topFilesMax
                                $topFiles = New-Object 'System.Collections.Generic.List[PSCustomObject]'
                                foreach ($s in $sorted) { $topFiles.Add($s) }
                                $topFilesMin = $topFiles[$topFiles.Count - 1].Size
                            }
                        }
                    } catch {}
                }
            } catch {}

            try {
                foreach ($sub in $di.EnumerateDirectories()) {
                    if ($MaxDepth -le 0 -or $depth -lt $MaxDepth) {
                        $stack.Push($sub.FullName)
                        $depthStack.Push($depth + 1)
                    }
                }
            } catch {}
        }

        $folderLocalSizes[$dir] = $localSize
        $folderAttribs[$dir]    = $attrib
        $scannedBytes += $localSize
        $scannedDirs++

        if (-not $Quiet) {
            $now = [DateTime]::Now
            if (($now - $lastProgress).TotalMilliseconds -gt 400) {
                Write-Progress -Activity "Varrendo $RootPath" `
                    -Status "$scannedDirs pastas | $scannedFiles arquivos | $(Format-FileSize $scannedBytes)" `
                    -PercentComplete -1
                $lastProgress = $now
            }
        }
    }

    Write-Progress -Activity "Varrendo $RootPath" -Completed

    # Agregacao bottom-up: caminhos mais profundos primeiro
    $allPaths = $folderLocalSizes.Keys | Sort-Object { $_.Split('\').Count } -Descending
    $folderTotalSizes = [System.Collections.Generic.Dictionary[string,long]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $allPaths) { $folderTotalSizes[$p] = $folderLocalSizes[$p] }
    foreach ($p in $allPaths) {
        $parent = [System.IO.Path]::GetDirectoryName($p)
        if ($parent -and $folderTotalSizes.ContainsKey($parent)) {
            $folderTotalSizes[$parent] += $folderTotalSizes[$p]
        }
    }

    # Top N arquivos final
    $finalFiles = $topFiles | Sort-Object Size -Descending | Select-Object -First 10

    return @{
        FolderTotalSizes = $folderTotalSizes
        FolderAttribs    = $folderAttribs
        TopFiles         = $finalFiles
        TotalBytes       = $scannedBytes
        TotalDirs        = $scannedDirs
        TotalFiles       = $scannedFiles
    }
}

# ---------------------------------------------------------------------------
# Estimativa de espaco desperdicado
# ---------------------------------------------------------------------------

function Get-WasteEstimates {
    [CmdletBinding()]
    param()
    function FolderSize([string]$p) {
        if (-not (Test-Path $p -ErrorAction SilentlyContinue)) { return [long]0 }
        $s = [long]0
        $stack = New-Object 'System.Collections.Generic.Stack[string]'
        $stack.Push($p)
        while ($stack.Count -gt 0) {
            $d = $stack.Pop()
            try {
                [System.IO.Directory]::GetFiles($d) | ForEach-Object {
                    try { $s += (New-Object System.IO.FileInfo($_)).Length } catch {}
                }
                [System.IO.Directory]::GetDirectories($d) | ForEach-Object { $stack.Push($_) }
            } catch {}
        }
        return $s
    }

    $items = @(
        [PSCustomObject]@{ Categoria = "Temporários do sistema";        Paths = @("$env:SystemRoot\Temp"); Note = "Seguros para remocao periodica" }
        [PSCustomObject]@{ Categoria = "Temporários do usuario (%TEMP%)"; Paths = @($env:TEMP, "$env:LOCALAPPDATA\Temp"); Note = "Remover com sessao fechada" }
        [PSCustomObject]@{ Categoria = "Dumps de memoria";              Paths = @("$env:SystemRoot\Minidump","$env:SystemRoot\MEMORY.DMP"); Note = "Remover apos analise do problema" }
        [PSCustomObject]@{ Categoria = "Cache Windows Update";          Paths = @("$env:SystemRoot\SoftwareDistribution\Download"); Note = "Requer parada dos servicos wu/bits" }
        [PSCustomObject]@{ Categoria = "Instalacao anterior (Windows.old)"; Paths = @("$env:SystemDrive\Windows.old"); Note = "Remover apos confirmar upgrade estavel" }
        [PSCustomObject]@{ Categoria = "Arquivo de hibernacao";         Paths = @("$env:SystemDrive\hiberfil.sys"); Note = "Liberar com: powercfg /h off" }
        [PSCustomObject]@{ Categoria = "Arquivo de paginacao";          Paths = @("$env:SystemDrive\pagefile.sys"); Note = "Informativo — nao remover manualmente" }
        [PSCustomObject]@{ Categoria = "Lixeira";                       Paths = @("$env:SystemDrive\`$Recycle.Bin"); Note = "Esvaziar via Clear-RecycleBin" }
        [PSCustomObject]@{ Categoria = "Logs CBS antigos";              Paths = @("$env:SystemRoot\Logs\CBS"); Note = "Manter CBS.log ativo; remover os demais >15d" }
        [PSCustomObject]@{ Categoria = "Logs DISM";                     Paths = @("$env:SystemRoot\Logs\DISM"); Note = "Seguros para remocao" }
        [PSCustomObject]@{ Categoria = "WinSxS (Component Store)";      Paths = @("$env:SystemRoot\WinSxS"); Note = "Usar DISM /StartComponentCleanup — NUNCA remover manualmente" }
    )

    # Caches por usuario
    $userCaches = @(
        [PSCustomObject]@{ Categoria = "Cache Google Chrome";   SubPath = "AppData\Local\Google\Chrome\User Data\Default\Cache"; Note = "Regenerado pelo navegador" }
        [PSCustomObject]@{ Categoria = "Cache Microsoft Edge";  SubPath = "AppData\Local\Microsoft\Edge\User Data\Default\Cache"; Note = "Regenerado pelo navegador" }
        [PSCustomObject]@{ Categoria = "Cache Mozilla Firefox"; SubPath = "AppData\Local\Mozilla\Firefox"; Note = "Gerenciar via browser: about:preferences#privacy" }
        [PSCustomObject]@{ Categoria = "Cache miniaturas";      SubPath = "AppData\Local\Microsoft\Windows\Explorer"; Note = "Regenerado pelo Explorer" }
    )

    $results = New-Object 'System.Collections.Generic.List[PSCustomObject]'

    foreach ($item in $items) {
        $sz = [long]0
        foreach ($p in $item.Paths) { $sz += FolderSize $p }
        $results.Add([PSCustomObject]@{
            Categoria = $item.Categoria
            SizeBytes = $sz
            SizeDisp  = Format-FileSize $sz
            Note      = $item.Note
        })
    }

    foreach ($uc in $userCaches) {
        $sz = [long]0
        Get-ChildItem "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Join-Path $_.FullName $uc.SubPath
            if (Test-Path $p) { $sz += FolderSize $p }
        }
        $results.Add([PSCustomObject]@{
            Categoria = $uc.Categoria
            SizeBytes = $sz
            SizeDisp  = Format-FileSize $sz
            Note      = $uc.Note
        })
    }

    return $results | Sort-Object SizeBytes -Descending
}

# ---------------------------------------------------------------------------
# Exibicao console (estilo Baobab)
# ---------------------------------------------------------------------------

function Show-ConsoleReport {
    [CmdletBinding()]
    param([object]$ScanResult, [object]$DriveInfo, [object[]]$Waste)

    $driveTotal  = $DriveInfo.TotalSize
    $driveFree   = $DriveInfo.TotalFreeSpace
    $driveUsed   = $driveTotal - $driveFree
    $drivePct    = if ($driveTotal -gt 0) { [int]($driveUsed / $driveTotal * 100) } else { 0 }
    $driveLetter = $DriveInfo.Name

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Analise de Espaco — $driveLetter  Total: $(Format-FileSize $driveTotal)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host (" Usado: $(Format-FileSize $driveUsed) ($drivePct%)   Livre: $(Format-FileSize $driveFree)") -ForegroundColor Gray
    $barColor = Get-BarColor $drivePct
    Write-Host (" $(Get-AsciiBar $drivePct 40) $drivePct%") -ForegroundColor $barColor
    Write-Host ""

    # Top 20 pastas
    $top20 = $ScanResult.FolderTotalSizes.GetEnumerator() |
        Sort-Object Value -Descending | Select-Object -First 20
    $maxSize = if ($top20) { ($top20 | Measure-Object -Property Value -Maximum).Maximum } else { 1 }

    Write-Host " Top 20 Pastas por Tamanho" -ForegroundColor Cyan
    Write-Host (" " + "-" * 78) -ForegroundColor DarkGray
    Write-Host (" {0,-6} {1,-10} {2,-5} {3,-25} {4,-8} {5}" -f "#", "Tamanho", "%Disk", "Barra", "Estado", "Pasta") -ForegroundColor Gray
    Write-Host (" " + "-" * 78) -ForegroundColor DarkGray

    $rank = 1
    foreach ($entry in $top20) {
        $path    = $entry.Key
        $sz      = $entry.Value
        $pct     = if ($driveTotal -gt 0) { [double]($sz) / $driveTotal * 100 } else { 0 }
        $barPct  = if ($maxSize -gt 0) { [double]($sz) / $maxSize * 100 } else { 0 }
        $bar     = Get-AsciiBar $barPct 20
        $attrib  = $ScanResult.FolderAttribs[$path]
        $isHidden = $attrib -band [System.IO.FileAttributes]::Hidden
        $isSystem = $attrib -band [System.IO.FileAttributes]::System
        $estado  = if ($isHidden) { "[OCULTO]" } elseif ($isSystem) { "[SISTEMA]" } else { "Normal" }
        $color   = if ($isHidden) { 'Yellow' } elseif ($isSystem) { 'DarkYellow' } else { 'White' }

        $line = " {0,-6} {1,-10} {2,-5} {3,-20} {4,-9}" -f "[$rank]", (Format-FileSize $sz), ("{0:N1}%" -f $pct), $bar, $estado
        Write-Host $line -NoNewline -ForegroundColor $color
        # Truncate path for display
        $dispPath = if ($path.Length -gt 45) { "..." + $path.Substring($path.Length - 42) } else { $path }
        Write-Host $dispPath -ForegroundColor $color
        $rank++
    }

    Write-Host ""
    Write-Host " Top 10 Arquivos por Tamanho" -ForegroundColor Cyan
    Write-Host (" " + "-" * 78) -ForegroundColor DarkGray
    Write-Host (" {0,-4} {1,-10} {2,-8} {3,-8} {4}" -f "#", "Tamanho", "Extensao", "Estado", "Caminho") -ForegroundColor Gray
    Write-Host (" " + "-" * 78) -ForegroundColor DarkGray

    $rank = 1
    foreach ($f in $ScanResult.TopFiles) {
        $estado = if ($f.IsHidden) { "[OCULTO]" } elseif ($f.IsSystem) { "[SISTEMA]" } else { "Normal" }
        $color  = if ($f.IsHidden) { 'Yellow' } elseif ($f.IsSystem) { 'DarkYellow' } else { 'White' }
        $dispPath = if ($f.Path.Length -gt 55) { "..." + $f.Path.Substring($f.Path.Length - 52) } else { $f.Path }
        Write-Host (" {0,-4} {1,-10} {2,-8} {3,-8} {4}" -f "[$rank]", (Format-FileSize $f.Size), $f.Ext, $estado, $dispPath) -ForegroundColor $color
        $rank++
    }

    Write-Host ""
    Write-Host " Estimativa de Espaco Desperdicado" -ForegroundColor Cyan
    Write-Host (" " + "-" * 78) -ForegroundColor DarkGray
    foreach ($w in ($Waste | Select-Object -First 8)) {
        $color = if ($w.SizeBytes -gt 1GB) { 'Red' } elseif ($w.SizeBytes -gt 100MB) { 'Yellow' } else { 'DarkGray' }
        Write-Host (" {0,-38} {1,-12} {2}" -f $w.Categoria, $w.SizeDisp, $w.Note) -ForegroundColor $color
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Relatorio HTML
# ---------------------------------------------------------------------------

function New-HtmlReport {
    [CmdletBinding()]
    param([object[]]$AllScans, [object[]]$AllWaste, [string]$ComputerName, [string]$ReportDate, [string]$OutputPath)

    # CSS artesanal com paleta Tailwind-inspired
# --- CSS -------------------------------------------------------------------
$css = @'
<style>
@font-face{font-family:'Inter';font-style:normal;font-weight:400;font-display:swap;src:local('Inter Regular'),local('Segoe UI'),local('sans-serif')}
@font-face{font-family:'Inter';font-style:normal;font-weight:700;font-display:swap;src:local('Inter Bold'),local('Segoe UI Bold'),local('sans-serif')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:400;font-display:swap;src:local('JetBrains Mono Regular'),local('Consolas'),local('monospace')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:700;font-display:swap;src:local('JetBrains Mono Bold'),local('Consolas Bold'),local('monospace')}
:root{--primary:#1e3a5f;--primary-lt:#2d5986;--accent:#2563eb;--success:#16a34a;--warning:#d97706;--danger:#dc2626;--bg:#f0f4f8;--surface:#fff;--border:#e2e8f0;--text:#1e293b;--muted:#64748b;--radius:8px;--font-sans:'Inter','Segoe UI',system-ui,-apple-system,sans-serif;--font-mono:'JetBrains Mono','Consolas',ui-monospace,monospace}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{font-family:var(--font-sans);background:var(--bg);color:var(--text);font-size:14px;line-height:1.5}
header{background:linear-gradient(135deg,var(--primary) 0%,var(--primary-lt) 100%);color:#fff;padding:2rem 2.5rem;display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:1rem}
header .title-block h1{font-size:1.6rem;font-weight:700;letter-spacing:-0.02em}
header .title-block p{opacity:.75;font-size:.85rem;margin-top:.25rem}
header .meta-block{text-align:right;font-size:.8rem;opacity:.8;line-height:1.8}
nav{background:var(--surface);border-bottom:2px solid var(--accent);position:sticky;top:0;z-index:100;box-shadow:0 2px 8px rgba(0,0,0,.08);overflow-x:auto;white-space:nowrap}
nav a{display:inline-block;padding:.65rem 1rem;color:var(--primary);text-decoration:none;font-size:.8rem;font-weight:600;border-bottom:2px solid transparent;transition:color .15s,border-color .15s}
nav a:hover{color:var(--accent);border-color:var(--accent)}
main{max-width:1400px;margin:1.5rem auto;padding:0 1.5rem}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:1rem;margin-bottom:1.5rem}
.card{background:var(--surface);border-radius:var(--radius);padding:1.1rem 1.25rem;box-shadow:0 1px 6px rgba(0,0,0,.07);border-left:4px solid var(--accent);transition:box-shadow .15s}
.card:hover{box-shadow:0 4px 14px rgba(0,0,0,.12)}
.card-icon{font-size:1.4rem;margin-bottom:.4rem}
.card-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:600}
.card-value{font-size:1.05rem;font-weight:700;color:var(--primary);margin-top:.2rem}
.card-sub{font-size:.75rem;color:var(--muted);margin-top:.15rem}
.section{background:var(--surface);border-radius:var(--radius);box-shadow:0 1px 6px rgba(0,0,0,.07);margin-bottom:1.25rem;overflow:hidden}
.section-hdr{background:var(--primary);color:#fff;padding:.75rem 1.5rem;font-size:.9rem;font-weight:700;display:flex;align-items:center;gap:.5rem}
.section-body{padding:1.25rem 1.5rem}
.sub{font-weight:700;color:var(--primary);font-size:.85rem;border-bottom:1px solid var(--border);padding-bottom:.35rem;margin:1.1rem 0 .6rem}
.sub:first-child{margin-top:0}
.kv-table{width:100%;border-collapse:collapse}
.kv-table th{width:220px;font-weight:600;font-size:.8rem;color:var(--muted);text-align:left;padding:.4rem .75rem .4rem 0;border-bottom:1px solid var(--border);vertical-align:top}
.kv-table td{font-size:.85rem;padding:.4rem 0;border-bottom:1px solid var(--border)}
.kv-table tr:last-child th,.kv-table tr:last-child td{border-bottom:none}
.kv-grid{display:grid;grid-template-columns:1fr 1fr;gap:0 2rem}
.data-table{width:100%;border-collapse:collapse;font-size:.82rem}
.data-table thead th{background:#f8fafc;color:var(--primary);font-weight:700;padding:.55rem 1rem;text-align:left;border-bottom:2px solid var(--border);white-space:nowrap}
.data-table tbody td{padding:.5rem 1rem;border-bottom:1px solid #f1f5f9}
.data-table tbody tr:last-child td{border-bottom:none}
.data-table tbody tr:hover td{background:#f8faff}
.scroll-wrap{overflow-x:auto}
.tall-wrap{max-height:420px;overflow-y:auto}
.disk-bar{background:#e2e8f0;border-radius:4px;height:8px;min-width:80px;overflow:hidden}
.disk-fill{height:100%;border-radius:4px;transition:width .3s}
.bar-ok{background:var(--success)}
.bar-warn{background:var(--warning)}
.bar-danger{background:var(--danger)}
.badge{display:inline-block;padding:.15em .55em;border-radius:4px;font-size:.72rem;font-weight:700;white-space:nowrap}
.badge-green{background:#dcfce7;color:#15803d}
.badge-yellow{background:#fef9c3;color:#92400e}
.badge-red{background:#fee2e2;color:#991b1b}
.badge-blue{background:#dbeafe;color:#1e40af}
.badge-gray{background:#f1f5f9;color:#475569}
.filter-wrap{margin-bottom:.75rem;display:flex;gap:.5rem;align-items:center}
.filter-input{flex:1;max-width:400px;padding:.45rem .75rem;border:1px solid var(--border);border-radius:var(--radius);font-size:.85rem;color:var(--text);outline:none;transition:border-color .15s}
.filter-input:focus{border-color:var(--accent)}
.filter-count{font-size:.78rem;color:var(--muted)}
.muted{color:var(--muted)}
.mono{font-family:var(--font-mono);font-size:.8rem;word-break:break-all}
.nowrap{white-space:nowrap}
.right{text-align:right}
footer{text-align:center;color:var(--muted);font-size:.78rem;padding:1.5rem;margin-top:.5rem}
@page{size:A4;margin:1.2cm 1.5cm}
@media print{body{background:#fff;font-size:11px}nav{display:none}.section{box-shadow:none;border:1px solid var(--border);break-inside:avoid;margin-bottom:.75rem}.tall-wrap{max-height:none;overflow:visible}.filter-wrap{display:none}header,.section-hdr{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style>
'@


    $driveCards = ""
    $driveSections = ""
    $allFolderRows = ""
    $allFileRows = ""
    $totalScanned = [long]0
    $totalAllDrives = [long]0
    $freeAllDrives  = [long]0

    foreach ($scan in $AllScans) {
        $di    = $scan.DriveInfo
        $total = $di.TotalSize
        $free  = $di.TotalFreeSpace
        $used  = $total - $free
        $pct   = if ($total -gt 0) { [int]($used / $total * 100) } else { 0 }
        $fillClass = if ($pct -ge 85) { 'bar-danger' } elseif ($pct -ge 70) { 'bar-warn' } else { 'bar-ok' }
        $totalScanned += $scan.Result.TotalBytes
        $totalAllDrives += $total
        $freeAllDrives  += $free

        # Card de resumo do drive
        $driveCards += @"
  <div class="card">
    <div class="card-icon">&#128190;</div>
    <div class="card-label">Volume $($di.Name)</div>
    <div class="card-value">$(Format-FileSize $total)</div>
    <div class="card-sub">$pct% ocupado — Livre: $(Format-FileSize $free)</div>
  </div>
"@

        # Secao detalhada do drive
        $driveSections += @"
<div class="section" id="drive-$($di.Name -replace ':','')">
  <div class="section-hdr">&#128190; Volume $($di.Name) — $(ConvertTo-HtmlSafe $di.VolumeLabel)</div>
  <div class="section-body">
    <div class="cards" style="margin-bottom:1rem">
      <div class="card" style="border-left-color:var(--accent)">
        <div class="card-label">Total</div>
        <div class="card-value">$(Format-FileSize $total)</div>
      </div>
      <div class="card" style="border-left-color:var(--success)">
        <div class="card-label">Livre</div>
        <div class="card-value" style="color:var(--success)">$(Format-FileSize $free)</div>
      </div>
      <div class="card" style="border-left-color:var(--danger)">
        <div class="card-label">Usado</div>
        <div class="card-value" style="color:var(--danger)">$(Format-FileSize $used)</div>
      </div>
      <div class="card" style="border-left-color:var(--warning)">
        <div class="card-label">Ocupacao</div>
        <div class="card-value">$pct%</div>
      </div>
      <div class="card">
        <div class="card-label">Pastas</div>
        <div class="card-value">$($scan.Result.TotalDirs)</div>
      </div>
      <div class="card">
        <div class="card-label">Arquivos</div>
        <div class="card-value">$($scan.Result.TotalFiles)</div>
      </div>
    </div>
    <div class="disk-bar"><div class="disk-fill $fillClass" style="width:$pct%"></div></div>
    <p class="note" style="margin-top:.4rem">$pct% utilizado — $(Format-FileSize $used) de $(Format-FileSize $total)</p>
  </div>
</div>
"@

        # Top 20 pastas para este drive
        $top20 = $scan.Result.FolderTotalSizes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20
        $maxSz = if ($top20) { ($top20 | Measure-Object -Property Value -Maximum).Maximum } else { 1 }
        $rank  = 1
        foreach ($entry in $top20) {
            $sz      = $entry.Value
            $pctDisk = if ($total -gt 0) { [int]($sz / $total * 100) } else { 0 }
            $pctBar  = if ($maxSz -gt 0) { [int]($sz / $maxSz * 100) } else { 0 }
            $attrib  = $scan.Result.FolderAttribs[$entry.Key]
            $isHid   = ($attrib -band [System.IO.FileAttributes]::Hidden) -ne 0
            $isSys   = ($attrib -band [System.IO.FileAttributes]::System) -ne 0
            $badge   = if ($isHid) { '<span class="badge badge-yellow">Oculto</span>' } `
                       elseif ($isSys) { '<span class="badge badge-red">Sistema</span>' } `
                       else { '<span class="badge badge-green">Normal</span>' }
            $allFolderRows += "<tr><td>$rank</td><td class='sz'>$(Format-FileSize $sz)</td><td class='pct'>$pctDisk%</td><td><div class='disk-bar' style='width:80px;display:inline-block'><div class='disk-fill bar-ok' style='width:$pctBar%'></div></div></td><td>$badge</td><td class='mono'>$(ConvertTo-HtmlSafe $entry.Key)</td></tr>"
            $rank++
        }
    }

    # Top 10 arquivos globais (todos os drives combinados)
    $allTopFiles = @()
    foreach ($scan in $AllScans) { $allTopFiles += $scan.Result.TopFiles }
    $finalTop10 = $allTopFiles | Sort-Object Size -Descending | Select-Object -First 10

    $fileRank = 1
    foreach ($f in $finalTop10) {
        $badge = if ($f.IsHidden) { '<span class="badge badge-yellow">Oculto</span>' } `
                 elseif ($f.IsSystem) { '<span class="badge badge-red">Sistema</span>' } `
                 else { '<span class="badge badge-green">Normal</span>' }
        $allFileRows += "<tr><td>$fileRank</td><td class='sz'>$(Format-FileSize $f.Size)</td><td>$(ConvertTo-HtmlSafe $f.Ext)</td><td>$badge</td><td class='mono'>$(ConvertTo-HtmlSafe $f.Path)</td></tr>"
        $fileRank++
    }

    # Linhas de desperdicio
    $wasteRows = ""
    $wasteTotal = [long]0
    foreach ($w in $AllWaste) {
        $wasteTotal += $w.SizeBytes
        $cls = if ($w.SizeBytes -gt 1GB) { 'waste-high' } elseif ($w.SizeBytes -gt 50MB) { 'waste-mid' } else { 'waste-low' }
        $wasteRows += "<tr><td>$(ConvertTo-HtmlSafe $w.Categoria)</td><td class='sz $cls'>$($w.SizeDisp)</td><td class='note'>$(ConvertTo-HtmlSafe $w.Note)</td></tr>"
    }

    # Cards de resumo global
    $usedAllDrives = $totalAllDrives - $freeAllDrives
    $pctGlobal = if ($totalAllDrives -gt 0) { [int]($usedAllDrives / $totalAllDrives * 100) } else { 0 }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Analise de Espaco — $ComputerName</title>
$css
</head>
<body>
<header>
  <div class="title-block">
    <h1>&#128190; Analise de Espaco em Disco</h1>
    <p>$(ConvertTo-HtmlSafe $ComputerName) — $ReportDate</p>
  </div>
  <div class="meta-block">
    <div><strong>$ComputerName</strong></div>
    <div>Gerado em: $ReportDate</div>
    <div>Versao: $($script:ScriptVersion)</div>
    <div>Somente leitura — nenhuma alteracao realizada</div>
  </div>
</header>
<nav>
  <a href="#resumo">&#128202; Resumo</a>
  <a href="#limpeza">&#128465; Desperdicio</a>
  <a href="#pastas">&#128193; Pastas</a>
  <a href="#arquivos">&#128196; Arquivos</a>
</nav>
<main>
<div class="cards" id="resumo">
  <div class="card" style="border-left-color:var(--accent)">
    <div class="card-icon">&#128190;</div>
    <div class="card-label">Espaco Total</div>
    <div class="card-value">$(Format-FileSize $totalAllDrives)</div>
    <div class="card-sub">$($AllScans.Count) volume(s)</div>
  </div>
  <div class="card" style="border-left-color:var(--success)">
    <div class="card-icon">&#9989;</div>
    <div class="card-label">Espaco Livre</div>
    <div class="card-value" style="color:var(--success)">$(Format-FileSize $freeAllDrives)</div>
    <div class="card-sub">$([int](($freeAllDrives / [math]::Max(1,$totalAllDrives)) * 100))% livre</div>
  </div>
  <div class="card" style="border-left-color:var(--danger)">
    <div class="card-icon">&#9888;</div>
    <div class="card-label">Espaco Usado</div>
    <div class="card-value" style="color:var(--danger)">$(Format-FileSize $usedAllDrives)</div>
    <div class="card-sub">$pctGlobal% ocupado</div>
  </div>
  <div class="card" style="border-left-color:var(--warning)">
    <div class="card-icon">&#128465;</div>
    <div class="card-label">Desperdicio Estimado</div>
    <div class="card-value" style="color:var(--warning)">$(Format-FileSize $wasteTotal)</div>
    <div class="card-sub">$(@($AllWaste).Count) categorias</div>
  </div>
  <div class="card">
    <div class="card-icon">&#128193;</div>
    <div class="card-label">Pastas Varridas</div>
    <div class="card-value">$("{0:N0}" -f $totalScanned)</div>
    <div class="card-sub">Todos os volumes</div>
  </div>
  <div class="card">
    <div class="card-icon">&#128196;</div>
    <div class="card-label">Maior Arquivo</div>
    <div class="card-value">$(if ($finalTop10.Count -gt 0) { Format-FileSize $finalTop10[0].Size } else { '&mdash;' })</div>
    <div class="card-sub">$(if ($finalTop10.Count -gt 0) { ConvertTo-HtmlSafe $finalTop10[0].Path } else { '' })</div>
  </div>
</div>

$driveSections

<div class="section" id="limpeza">
  <div class="section-hdr">&#128465; Estimativa de Espaco Desperdicado — Total: $(Format-FileSize $wasteTotal)</div>
  <div class="section-body">
    <p class="note" style="margin-bottom:1rem">Somente leitura — nenhuma acao foi realizada. Use os scripts do modulo maintenance para remocao segura.</p>
    <div style="overflow-x:auto">
    <table class="data-table">
      <thead><tr><th>Categoria</th><th>Tamanho Estimado</th><th>Observacao</th></tr></thead>
      <tbody>$wasteRows</tbody>
    </table>
    </div>
  </div>
</div>

<div class="section" id="pastas">
  <div class="section-hdr">&#128193; Top 20 Pastas por Tamanho Total</div>
  <div class="section-body">
    <div style="overflow-x:auto">
    <table class="data-table">
      <thead><tr><th>#</th><th>Tamanho</th><th>% Disco</th><th>Barra</th><th>Estado</th><th>Caminho</th></tr></thead>
      <tbody>$allFolderRows</tbody>
    </table>
    </div>
  </div>
</div>

<div class="section" id="arquivos">
  <div class="section-hdr">&#128196; Top 10 Arquivos por Tamanho</div>
  <div class="section-body">
    <div style="overflow-x:auto">
    <table class="data-table">
      <thead><tr><th>#</th><th>Tamanho</th><th>Extensao</th><th>Estado</th><th>Caminho completo</th></tr></thead>
      <tbody>$allFileRows</tbody>
    </table>
    </div>
  </div>
</div>
</main>
<footer>Gerado por $($script:ScriptName) $($script:ScriptVersion) em $ReportDate — somente leitura, nenhuma alteracao foi realizada.</footer>
</body>
</html>
"@

    Write-TextFileUtf8 -Path $OutputPath -Content $html
}

function Convert-ToPdf {
    [CmdletBinding()]
    param([string]$HtmlPath, [string]$PdfPath)
    $browsers = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )
    $exe = $browsers | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) {
        Write-Warn "Chrome/Edge nao encontrado. Abra o HTML e use Ctrl+P para exportar PDF."
        return
    }
    $fileUrl = "file:///" + $HtmlPath.Replace('\','/')
    $browserArgs = @("--headless","--disable-gpu","--no-pdf-header-footer","--print-to-pdf=`"$PdfPath`"","`"$fileUrl`"")
    $proc = Start-Process -FilePath $exe -ArgumentList $browserArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
    if (Test-Path $PdfPath) {
        Write-Ok "PDF gerado: $PdfPath ($([int]((Get-Item $PdfPath).Length/1KB)) KB)"
    }
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if ($Help)    { Show-Help; exit 0 }
if ($Version) { Write-Info "Versao: $ScriptVersion"; exit 0 }

if (-not (Test-IsAdministrator)) {
    Write-Warn "Privilegio de Administrador recomendado para acessar pastas protegidas. Solicitando elevacao..."
    $relaunchCommand = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunchCommand) -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'utilidades'
$Path          = $ReportSession.Path
$LogDir        = $ReportSession.LogsPath
$LogFile       = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$([System.IO.Path]::GetFileNameWithoutExtension($ScriptName)).log"

if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }

$EventLogFile = $LogFile -replace '\.log$', '-eventos.log'
$transcriptActive = $false
try {
    Start-Transcript -Path $LogFile -ErrorAction Stop
    $transcriptActive = $true
} catch {
    Write-Warn "Nao foi possivel iniciar log: $($_.Exception.Message)"
}

Write-Title "Analise de Espaco em Disco — $ScriptVersion"
Write-ScriptLog -Message "Inicio da analise de espaco em disco." -LogPath $EventLogFile

# Selecionar drives
if ($Drive -and $Drive.Count -gt 0) {
    $targetDrives = $Drive | ForEach-Object {
        $l = $_.Trim(':').ToUpper()
        Get-PSDrive -Name $l -PSProvider FileSystem -ErrorAction SilentlyContinue |
            ForEach-Object { [System.IO.DriveInfo]::new("$($_.Name):\") }
    }
} else {
    $targetDrives = [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }
}

if (-not $targetDrives) {
    Write-Fail "Nenhum volume encontrado para varredura."
    Write-ScriptLog -Message "Nenhum volume encontrado para varredura." -Level ERROR -LogPath $EventLogFile
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

Write-Info "Volumes: $($targetDrives.Name -join ', ')"

# Varrer cada drive
$allScans = New-Object 'System.Collections.Generic.List[PSCustomObject]'
foreach ($di in $targetDrives) {
    Write-Info "Varrendo $($di.Name) ($($di.VolumeLabel)) — $(Format-FileSize $di.TotalSize) total... (pode demorar varios minutos)"
    $t0     = [DateTime]::Now
    $result = Invoke-DiskScan -RootPath $di.RootDirectory.FullName -Quiet:$Silent -MaxDepth $MaxDepth
    $elapsed = [int]([DateTime]::Now - $t0).TotalSeconds
    Write-Ok "Concluido em $($elapsed)s: $($result.TotalDirs) pastas, $($result.TotalFiles) arquivos, $(Format-FileSize $result.TotalBytes)"
    Write-ScriptLog -Message "Varredura de $($di.Name) concluida em $($elapsed)s: $($result.TotalDirs) pastas, $($result.TotalFiles) arquivos, $(Format-FileSize $result.TotalBytes)." -LogPath $EventLogFile
    $allScans.Add([PSCustomObject]@{ DriveInfo = $di; Result = $result })
}

# Estimativa de espaco desperdicado
Write-Info "Calculando estimativas de espaco desperdicado..."
$waste = Get-WasteEstimates

# Relatorio console
foreach ($scan in $allScans) {
    Show-ConsoleReport -ScanResult $scan.Result -DriveInfo $scan.DriveInfo -Waste $waste
}

# Relatorio HTML
$ts       = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
$htmlFile = Join-Path $Path "$ts-relatorio-analise-espaco-disco.html"
$pdfFile  = $htmlFile -replace '\.html$','.pdf'
$dateStr  = (Get-Date).ToString('dd/MM/yyyy HH:mm')

Write-Info "Gerando relatorio HTML..."
New-HtmlReport -AllScans $allScans -AllWaste $waste `
    -ComputerName $env:COMPUTERNAME -ReportDate $dateStr -OutputPath $htmlFile
Write-Ok "HTML: $htmlFile"
Write-ScriptLog -Message "Relatorio HTML gerado: $htmlFile" -LogPath $EventLogFile

if (-not $NaoPDF) {
    Write-Info "Convertendo para PDF..."
    Convert-ToPdf -HtmlPath $htmlFile -PdfPath $pdfFile
    if (Test-Path $pdfFile) { Write-ScriptLog -Message "Relatorio PDF gerado: $pdfFile" -LogPath $EventLogFile }
}

Write-Section "Analise concluida"
Write-Ok "HTML  : $htmlFile"
if (-not $NaoPDF -and (Test-Path $pdfFile)) {
    Write-Ok "PDF   : $pdfFile"
}
Write-Ok "Log   : $LogFile"
Write-Info "Somente leitura — nenhuma alteracao foi realizada no sistema."

Write-ScriptLog -Message "Analise de espaco em disco finalizada." -LogPath $EventLogFile

if ($transcriptActive) { Stop-Transcript }
