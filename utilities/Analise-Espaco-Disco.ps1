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

.FUNCIONALIDADES
    - Varre todos os volumes locais fixos (ou drive especificado com -Drive).
    - Ignora pontos de reparse (juncoes, links simbolicos) para evitar loops.
    - Marca pastas e arquivos ocultos no relatorio.
    - Detecta categorias de espaco desperdicado: temp, cache, dumps, logs antigos,
      Windows.old, hiberfil.sys, lixeira, cache de browsers, WinSxS.
    - Top 20 pastas por tamanho total com barra visual proporcional.
    - Top 10 arquivos por tamanho individual.
    - Relatorio HTML salvo na pasta padronizada do toolkit com conversao opcional para PDF.
    - Log completo da execucao em logs da sessao.

.USO
    Varrer todos os volumes locais:
        .\Analise-Espaco-Disco.ps1

    Varrer apenas o volume C::
        .\Analise-Espaco-Disco.ps1 -Drive C

    Salvar relatorio em outro diretorio:
        .\Analise-Espaco-Disco.ps1 -OutputDir "D:\Relatorios"

    Gerar apenas HTML (sem PDF):
        .\Analise-Espaco-Disco.ps1 -NaoPDF

.NOTAS
    Requer privilegios de Administrador para acessar pastas protegidas do sistema.
    O tempo de varredura varia com o tamanho do disco (tipicamente 1-5 min para C:).
    Testado no Windows 10 Pro (21H2+) e Windows 11 Pro.
#>
param (
    [switch]$Help,
    [switch]$Version,
    [string[]]$Drive,
    [string]$OutputDir,
    [switch]$NaoPDF,
    [switch]$Silent
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
chcp 65001 | Out-Null

$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$ToolkitModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $ToolkitModulePath -Force -ErrorAction Stop

$ScriptVersion = "v1.0"
$ScriptName    = $MyInvocation.MyCommand.Name
$ReportSession = $null
$LogDir        = $null
$LogFile       = $null

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------

function Show-Help {
    [CmdletBinding()]
    Write-Host ""
    Write-Host "Analise de Espaco em Disco — $script:ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Drive '<letra>'   Volume a varrer (ex: C). Padrao: todos os locais fixos."
    Write-Host "  -OutputDir '<dir>' Raiz de relatorios. Padrao: ReportsRoot persistente ou C:\WBA\Relatorios"
    Write-Host "  -NaoPDF            Gera apenas HTML sem converter para PDF."
    Write-Host "  -Silent            Sem saida de progresso no console."
    Write-Host "  -Help              Esta ajuda."
    Write-Host "  -Version           Versao do script."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Drive C"
    Write-Host "  .\$ScriptName -Drive C,D -OutputDir D:\Relatorios -NaoPDF"
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
    param([string]$RootPath, [switch]$Quiet)

    $folderLocalSizes = [System.Collections.Generic.Dictionary[string,long]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $folderAttribs = [System.Collections.Generic.Dictionary[string,int]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $topFiles = New-Object 'System.Collections.Generic.List[PSCustomObject]'
    $topFilesMax = 200

    $stack   = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($RootPath)
    $scannedDirs  = [long]0
    $scannedFiles = [long]0
    $scannedBytes = [long]0
    $lastProgress = [DateTime]::Now

    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $localSize = [long]0
        $attrib = 0

        try {
            $di = New-Object System.IO.DirectoryInfo($dir)
            $attrib = [int]$di.Attributes
            # Skip reparse points (junctions, symlinks) to avoid loops/double-counting
            if ($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $folderLocalSizes[$dir] = [long]0
                $folderAttribs[$dir] = $attrib
                continue
            }
        } catch {}

        try {
            foreach ($file in [System.IO.Directory]::GetFiles($dir)) {
                try {
                    $fi = New-Object System.IO.FileInfo($file)
                    $sz = $fi.Length
                    $localSize  += $sz
                    $scannedFiles++

                    if ($topFiles.Count -lt $topFilesMax -or $sz -gt ($topFiles | Measure-Object -Property Size -Minimum).Minimum) {
                        $topFiles.Add([PSCustomObject]@{
                            Path      = $file
                            Name      = $fi.Name
                            Dir       = $dir
                            Ext       = $fi.Extension.ToLower()
                            Size      = $sz
                            IsHidden  = ($fi.Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0
                            IsSystem  = ($fi.Attributes -band [System.IO.FileAttributes]::System) -ne 0
                        })
                        if ($topFiles.Count -gt $topFilesMax * 2) {
                            $sorted = $topFiles | Sort-Object Size -Descending | Select-Object -First $topFilesMax
                            $topFiles = New-Object 'System.Collections.Generic.List[PSCustomObject]'
                            $sorted | ForEach-Object { $topFiles.Add($_) }
                        }
                    }
                } catch {}
            }
        } catch {}

        try {
            foreach ($sub in [System.IO.Directory]::GetDirectories($dir)) {
                $stack.Push($sub)
            }
        } catch {}

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
        Get-ChildItem "C:\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
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

    $driveTotal  = $DriveInfo.Size
    $driveFree   = $DriveInfo.FreeSpace
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

    $css = @'
:root{--primary:#0078d4;--success:#107c10;--warn:#d83b01;--text:#201f1e;--muted:#605e5c;--bg:#f3f3f3;--card:#fff;--border:#edebe9;--radius:4px}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',sans-serif;font-size:14px;background:var(--bg);color:var(--text)}
header{background:var(--primary);color:#fff;padding:20px 32px}
header h1{font-size:22px;font-weight:600}
header p{font-size:12px;opacity:.85;margin-top:4px}
main{max-width:1200px;margin:0 auto;padding:24px 16px}
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:20px;margin-bottom:20px}
.card h2{font-size:15px;font-weight:600;color:var(--primary);margin-bottom:14px;padding-bottom:8px;border-bottom:1px solid var(--border)}
.drive-bar{height:18px;background:#edebe9;border-radius:9px;overflow:hidden;margin:6px 0}
.drive-fill{height:100%;border-radius:9px;transition:width .4s}
.fill-ok{background:#107c10}.fill-warn{background:#d83b01}.fill-mid{background:#e67e00}
.stats{display:flex;gap:20px;flex-wrap:wrap;margin-bottom:16px}
.stat{flex:1;min-width:120px;background:#f0f6ff;border-radius:4px;padding:12px 16px;text-align:center}
.stat-val{font-size:22px;font-weight:700;color:var(--primary)}
.stat-lbl{font-size:11px;color:var(--muted);margin-top:2px}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#f7f7f7;padding:8px 10px;text-align:left;font-weight:600;border-bottom:2px solid var(--border);white-space:nowrap}
td{padding:7px 10px;border-bottom:1px solid var(--border);vertical-align:middle}
tr:hover td{background:#faf9f8}
.mini-bar{display:inline-block;height:8px;border-radius:4px;background:var(--primary);vertical-align:middle;margin-right:6px}
.sz{font-weight:600;color:var(--primary);white-space:nowrap}
.pct{color:var(--muted);font-size:12px}
.badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:600}
.badge-ok{background:#dff6dd;color:#107c10}
.badge-hidden{background:#fff4ce;color:#835b00}
.badge-system{background:#fde7e9;color:#c0392b}
.waste-high{color:#d83b01;font-weight:600}
.waste-mid{color:#e67e00}
.waste-low{color:var(--muted)}
.path{font-family:'Consolas',monospace;font-size:12px;word-break:break-all}
.note{font-size:11px;color:var(--muted)}
footer{text-align:center;padding:20px;font-size:11px;color:var(--muted)}
@media print{header{background:var(--primary)!important;print-color-adjust:exact}th{background:#f7f7f7!important;print-color-adjust:exact}.mini-bar{print-color-adjust:exact}}
'@

    $driveRows = ""
    $allFolderRows = ""
    $allFileRows = ""
    $totalScanned = [long]0

    foreach ($scan in $AllScans) {
        $di    = $scan.DriveInfo
        $total = $di.Size
        $free  = $di.FreeSpace
        $used  = $total - $free
        $pct   = if ($total -gt 0) { [int]($used / $total * 100) } else { 0 }
        $fillClass = if ($pct -ge 85) { 'fill-warn' } elseif ($pct -ge 65) { 'fill-mid' } else { 'fill-ok' }
        $totalScanned += $scan.Result.TotalBytes

        $driveRows += @"
<div class="card">
<h2>Volume $($di.Name) — $($di.VolumeLabel)</h2>
<div class="stats">
  <div class="stat"><div class="stat-val">$(Format-FileSize $total)</div><div class="stat-lbl">Total</div></div>
  <div class="stat"><div class="stat-val" style="color:#107c10">$(Format-FileSize $free)</div><div class="stat-lbl">Livre</div></div>
  <div class="stat"><div class="stat-val" style="color:#d83b01">$(Format-FileSize $used)</div><div class="stat-lbl">Usado</div></div>
  <div class="stat"><div class="stat-val">$pct%</div><div class="stat-lbl">Ocupacao</div></div>
  <div class="stat"><div class="stat-val">$($scan.Result.TotalDirs)</div><div class="stat-lbl">Pastas varridas</div></div>
  <div class="stat"><div class="stat-val">$($scan.Result.TotalFiles)</div><div class="stat-lbl">Arquivos</div></div>
</div>
<div class="drive-bar"><div class="drive-fill $fillClass" style="width:$pct%"></div></div>
<p class="note">$pct% utilizado — $pct% de $(Format-FileSize $total)</p>
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
            $badge   = if ($isHid) { '<span class="badge badge-hidden">Oculto</span>' } `
                       elseif ($isSys) { '<span class="badge badge-system">Sistema</span>' } `
                       else { '<span class="badge badge-ok">Normal</span>' }
            $allFolderRows += "<tr><td>$rank</td><td class='sz'>$(Format-FileSize $sz)</td><td class='pct'>$pctDisk%</td><td><div class='mini-bar' style='width:$([Math]::Max(2,$pctBar))px'></div></td><td>$badge</td><td class='path'>$(ConvertTo-HtmlSafe $entry.Key)</td></tr>"
            $rank++
        }
    }

    # Top 10 arquivos globais (todos os drives combinados)
    $allTopFiles = @()
    foreach ($scan in $AllScans) { $allTopFiles += $scan.Result.TopFiles }
    $finalTop10 = $allTopFiles | Sort-Object Size -Descending | Select-Object -First 10

    $fileRank = 1
    foreach ($f in $finalTop10) {
        $badge = if ($f.IsHidden) { '<span class="badge badge-hidden">Oculto</span>' } `
                 elseif ($f.IsSystem) { '<span class="badge badge-system">Sistema</span>' } `
                 else { '<span class="badge badge-ok">Normal</span>' }
        $allFileRows += "<tr><td>$fileRank</td><td class='sz'>$(Format-FileSize $f.Size)</td><td>$(ConvertTo-HtmlSafe $f.Ext)</td><td>$badge</td><td class='path'>$(ConvertTo-HtmlSafe $f.Path)</td></tr>"
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

    $html = @"
<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Analise de Espaco — $ComputerName</title><style>$css</style></head>
<body>
<header>
  <h1>Analise de Espaco em Disco</h1>
  <p>Computador: <strong>$ComputerName</strong> &nbsp;|&nbsp; Data: <strong>$ReportDate</strong> &nbsp;|&nbsp; Script: $($script:ScriptVersion)</p>
</header>
<main>
$driveRows
<div class="card" id="limpeza">
<h2>Estimativa de Espaco Desperdicado — Total estimado: $(Format-FileSize $wasteTotal)</h2>
<p class="note" style="margin-bottom:12px">Somente leitura — nenhuma acao foi realizada. Use os scripts do modulo maintenance para remocao segura.</p>
<table><thead><tr><th>Categoria</th><th>Tamanho Estimado</th><th>Observacao</th></tr></thead>
<tbody>$wasteRows</tbody></table></div>

<div class="card" id="pastas">
<h2>Top 20 Pastas por Tamanho Total</h2>
<table><thead><tr><th>#</th><th>Tamanho</th><th>% Disco</th><th>Barra</th><th>Estado</th><th>Caminho</th></tr></thead>
<tbody>$allFolderRows</tbody></table></div>

<div class="card" id="arquivos">
<h2>Top 10 Arquivos por Tamanho</h2>
<table><thead><tr><th>#</th><th>Tamanho</th><th>Extensao</th><th>Estado</th><th>Caminho completo</th></tr></thead>
<tbody>$allFileRows</tbody></table></div>
</main>
<footer>Gerado por $($script:ScriptName) $($script:ScriptVersion) em $ReportDate — somente leitura, nenhuma alteracao foi realizada.</footer>
</body></html>
"@

    $html | Set-Content -Path $OutputPath -Encoding UTF8
}

function Convert-ToPdf {
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
        Write-Host "  Chrome/Edge nao encontrado. Abra o HTML e use Ctrl+P para exportar PDF." -ForegroundColor Yellow
        return
    }
    $fileUrl = "file:///" + $HtmlPath.Replace('\','/')
    $args = @("--headless","--disable-gpu","--no-pdf-header-footer","--print-to-pdf=`"$PdfPath`"","`"$fileUrl`"")
    $proc = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
    if (Test-Path $PdfPath) {
        Write-Host "  PDF gerado: $PdfPath ($([int]((Get-Item $PdfPath).Length/1KB)) KB)" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if ($Help)    { Show-Help; exit 0 }
if ($Version) { Write-Host "Versao: $ScriptVersion" -ForegroundColor Green; exit 0 }

if (-not (Test-IsAdministrator)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value.IsPresent) { "-$($kv.Key)" } }
        else { "-$($kv.Key)"; "$($kv.Value)" }
    }
    $allArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $OutputDir -ModuleName 'Utilities'
$OutputDir     = $ReportSession.Path
$LogDir        = $ReportSession.LogsPath
$LogFile       = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$([System.IO.Path]::GetFileNameWithoutExtension($ScriptName)).log"

if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$transcriptActive = $false
try {
    Start-Transcript -Path $LogFile -Encoding UTF8 -ErrorAction Stop
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar log: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Analise de Espaco em Disco — $ScriptVersion" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

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
    Write-Host "Nenhum volume encontrado para varredura." -ForegroundColor Red
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

Write-Host "Volumes: $($targetDrives.Name -join ', ')" -ForegroundColor Yellow
Write-Host ""

# Varrer cada drive
$allScans = New-Object 'System.Collections.Generic.List[PSCustomObject]'
foreach ($di in $targetDrives) {
    Write-Host "Varrendo $($di.Name) ($($di.VolumeLabel)) — $(Format-FileSize $di.Size) total..." -ForegroundColor Yellow
    $t0     = [DateTime]::Now
    $result = Invoke-DiskScan -RootPath $di.RootDirectory.FullName -Quiet:$Silent
    $elapsed = [int]([DateTime]::Now - $t0).TotalSeconds
    Write-Host "  Concluido em $($elapsed)s: $($result.TotalDirs) pastas, $($result.TotalFiles) arquivos, $(Format-FileSize $result.TotalBytes)" -ForegroundColor Green
    $allScans.Add([PSCustomObject]@{ DriveInfo = $di; Result = $result })
}

# Estimativa de espaco desperdicado
Write-Host ""
Write-Host "Calculando estimativas de espaco desperdicado..." -ForegroundColor Yellow
$waste = Get-WasteEstimates

# Relatorio console
foreach ($scan in $allScans) {
    Show-ConsoleReport -ScanResult $scan.Result -DriveInfo $scan.DriveInfo -Waste $waste
}

# Relatorio HTML
$ts       = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
$htmlFile = Join-Path $OutputDir "$ts-relatorio-analise-espaco-disco.html"
$pdfFile  = $htmlFile -replace '\.html$','.pdf'
$dateStr  = (Get-Date).ToString('dd/MM/yyyy HH:mm')

Write-Host "Gerando relatorio HTML..." -ForegroundColor Yellow
New-HtmlReport -AllScans $allScans -AllWaste $waste `
    -ComputerName $env:COMPUTERNAME -ReportDate $dateStr -OutputPath $htmlFile
Write-Host "  HTML: $htmlFile" -ForegroundColor Green

if (-not $NaoPDF) {
    Write-Host "Convertendo para PDF..." -ForegroundColor Yellow
    Convert-ToPdf -HtmlPath $htmlFile -PdfPath $pdfFile
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Analise concluida." -ForegroundColor Green
Write-Host " HTML  : $htmlFile" -ForegroundColor Green
if (-not $NaoPDF -and (Test-Path $pdfFile)) {
    Write-Host " PDF   : $pdfFile" -ForegroundColor Green
}
Write-Host " Log   : $LogFile" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

if ($transcriptActive) { Stop-Transcript }
