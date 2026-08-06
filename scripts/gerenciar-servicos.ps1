<#
.SYNOPSIS
    Gerenciamento de servicos Windows: listar, iniciar, parar, reiniciar e configurar.

.DESCRIPTION
    Gerencia servicos Windows de forma padronizada.
    Suporta: diagnostico, listagem, inicio, parada, reinicio, alteracao de
    inicializacao (Automatic/Manual/Disabled), alteracao de conta de logon e
    detalhes de servicos.

.PARAMETER Acao
    Acao a executar: Diagnostico (padrao), Listar, Iniciar, Parar, Reiniciar,
    ConfigurarInicializacao, ConfigurarConta, Detalhar.

.PARAMETER Servico
    Nome do servico para operacoes especificas.

.PARAMETER Filtro
    Filtra servicos por nome (wildcard). Ex.: 'W32*', '*Update*'.

.PARAMETER FiltroStatus
    Filtra por status: Running, Stopped, Paused.

.PARAMETER FiltroInicio
    Filtra por tipo de inicializacao: Automatic, Manual, Disabled.

.PARAMETER OrdenarPor
    Ordena por coluna: Nome, DisplayName, Status, StartType. Padrao: Nome.

.PARAMETER Decrescente
    Inverte a ordem de classificacao.

.PARAMETER Top
    Limita o numero de resultados exibidos. Padrao: 50.

.PARAMETER Interativo
    Forca modo interativo em Listar (padrao: ativo em terminal interativo).
    Navegacao: setas, PgUp/PgDn, Home/End, busca, filtro, ordenacao, paginacao.

.PARAMETER StartupType
    Tipo de inicializacao para ConfigurarInicializacao: Automatic, Manual, Disabled.

.PARAMETER Conta
    Conta de logon para ConfigurarConta. Built-in: LocalSystem, LocalService, NetworkService.

.PARAMETER Credencial
    Credencial segura da conta (necessaria para contas de dominio).

.PARAMETER DryRun
    Simula a acao sem executar.

.PARAMETER GerarHtml
    Gera relatorio HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatorio ao final (HTML se -GerarHtml, senao TXT).

.PARAMETER Path
    Diretorio raiz de relatorios.

.PARAMETER Help
    Exibe a ajuda e encerra.

.EXAMPLE
    .\gerenciar-servicos.ps1

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Listar

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Listar -Interativo

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Listar -Filtro 'W32*' -FiltroStatus Running

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Listar -OrdenarPor Status -Decrescente -Top 20
    # Lista estatica (nao interativa) limitada a 20 itens

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Parar -Servico Spooler

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao ConfigurarInicializacao -Servico WSearch -StartupType Disabled

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Detalhar -Servico W32Time

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.Services
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Listar', 'Iniciar', 'Parar', 'Reiniciar',
                 'ConfigurarInicializacao', 'ConfigurarConta', 'Detalhar')]
    [string]$Acao = 'Diagnostico',

    [string]$Servico,

    [ValidateSet('Automatic', 'Manual', 'Disabled')]
    [string]$StartupType,

    [string]$Conta,

    [pscredential]$Credencial,

    [string]$Filtro,

    [ValidateSet('Running', 'Stopped', 'Paused')]
    [string]$FiltroStatus,

    [ValidateSet('Automatic', 'Manual', 'Disabled')]
    [string]$FiltroInicio,

    [ValidateSet('Nome', 'DisplayName', 'Status', 'StartType')]
    [string]$OrdenarPor = 'Nome',

    [switch]$Decrescente,

    [ValidateRange(5, 500)]
    [int]$Top = 50,

    [switch]$Interativo,

    [switch]$DryRun,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Alias('DiretorioSaida')]
    [string]$Path,

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
    Write-Host "Gerenciamento de Servicos Windows" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$script:ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Acao <valor>              Diagnostico (padrao), Listar, Iniciar, Parar, Reiniciar,"
    Write-Host "                             ConfigurarInicializacao, ConfigurarConta, Detalhar."
    Write-Host "  -Servico '<nome>'          Nome do servico para operacoes especificas."
    Write-Host "  -Filtro '<padrao>'         Filtra servicos por nome (wildcard). Ex.: 'W32*', '*Update*'."
    Write-Host "  -FiltroStatus <valor>      Filtra por status: Running, Stopped, Paused."
    Write-Host "  -FiltroInicio <valor>      Filtra por inicializacao: Automatic, Manual, Disabled."
    Write-Host "  -OrdenarPor <valor>        Nome, DisplayName, Status, StartType. Padrao: Nome."
    Write-Host "  -Decrescente               Inverte a ordem de classificacao."
    Write-Host "  -Top <n>                   Limita o numero de resultados exibidos. Padrao: 50."
    Write-Host "  -Interativo                Forca modo interativo em Listar (padrao em terminal interativo)."
    Write-Host "  -StartupType <valor>       Automatic, Manual ou Disabled para ConfigurarInicializacao."
    Write-Host "  -Conta '<conta>'           Conta de logon para ConfigurarConta (LocalSystem, etc.)."
    Write-Host "  -Credencial                Credencial segura da conta (contas de dominio)."
    Write-Host "  -DryRun                    Simula a acao sem executar."
    Write-Host "  -GerarHtml                 Gera relatorio HTML adicional."
    Write-Host "  -AbrirRelatorio            Abre o relatorio ao final (HTML se -GerarHtml, senao TXT)."
    Write-Host "  -DiretorioSaida '<dir>'    Diretorio raiz de relatorios."
    Write-Host "  -Help                      Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$script:ScriptName"
    Write-Host "  .\$script:ScriptName -Acao Listar"
    Write-Host "  .\$script:ScriptName -Acao Listar -Interativo"
    Write-Host "  .\$script:ScriptName -Acao Listar -Filtro 'W32*' -FiltroStatus Running"
    Write-Host "  .\$script:ScriptName -Acao Listar -OrdenarPor Status -Decrescente -Top 20"
    Write-Host "  .\$script:ScriptName -Acao Parar -Servico Spooler"
    Write-Host "  .\$script:ScriptName -Acao ConfigurarInicializacao -Servico WSearch -StartupType Disabled"
    Write-Host "  .\$script:ScriptName -Acao Detalhar -Servico W32Time"
    Write-Host ""
}

if ($Help) {
    Show-Help
    exit 0
}

# === Dependencias: dot-source direto (nao depende de Import-Module) ===
$coreModuleRoot     = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$servicesModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Services'

foreach ($dir in @($coreModuleRoot, $servicesModuleRoot)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Host "[FALHA] Modulo nao encontrado: $dir" -ForegroundColor Red
        Write-Host "        Solucao: verifique o clone do repositorio em $ToolkitRoot" -ForegroundColor Yellow
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot, $servicesModuleRoot)) {
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

$actionRequiresAdmin = @('Iniciar', 'Parar', 'Reiniciar', 'ConfigurarInicializacao', 'ConfigurarConta')
if ($Acao -in $actionRequiresAdmin -and -not (Test-IsAdministrator)) {
    Write-Warning "A acao '$Acao' exige privilegios administrativos. Solicitando elevacao..."
    $command = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) -Verb RunAs
    exit 0
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'servicos'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Title "Gerenciamento de Servicos Windows"

if ($DryRun) {
    Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
    Write-Host ""
}

# ── Validacoes ─────────────────────────────────────────────────────────────

if ($Acao -in @('Iniciar', 'Parar', 'Reiniciar', 'ConfigurarInicializacao', 'ConfigurarConta', 'Detalhar')) {
    if ([string]::IsNullOrWhiteSpace($Servico)) {
        Write-Fail "Acao '$Acao' requer -Servico."
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

if ($Acao -eq 'ConfigurarInicializacao' -and [string]::IsNullOrWhiteSpace($StartupType)) {
        Write-Fail "Acao 'ConfigurarInicializacao' requer -StartupType."
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

if ($Acao -eq 'ConfigurarConta' -and [string]::IsNullOrWhiteSpace($Conta)) {
        Write-Fail "Acao 'ConfigurarConta' requer -Conta."
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

# ── Diagnostico ────────────────────────────────────────────────────────────

if ($Acao -eq 'Diagnostico') {
    Write-Section "Diagnostico de Servicos"

    $result = Invoke-ServiceManager -Acao Diagnostico
    $script:DiagnosticoResult = $result

    Write-Host ""
    if ($result.StoppedAuto.Count -gt 0) {
        Write-Warn "$($result.StoppedAuto.Count) servico(s) automatico(s) parado(s):"
        foreach ($s in $result.StoppedAuto) {
            Write-Host "  - $($s.Name) ($($s.DisplayName))" -ForegroundColor Yellow
        }
    }
    else {
        Write-Ok "Todos os servicos automaticos estao em execucao."
    }

    Write-Host ""
    Write-Ok "Diagnostico concluido: $($result.Message)"
}

# ── Listar ─────────────────────────────────────────────────────────────────

if ($Acao -eq 'Listar') {
    function Get-ServiceListView {
        param(
            [object[]]$Source,
            [string]$Search,
            [string]$StatusF,
            [string]$StartF,
            [string]$SortProp,
            [bool]$Desc
        )

        $view = @($Source)
        if (-not [string]::IsNullOrWhiteSpace($Search)) {
            $pattern = $Search
            if ($pattern -notmatch '[\*\?]') { $pattern = "*$pattern*" }
            $view = @($view | Where-Object {
                $_.Name -like $pattern -or $_.DisplayName -like $pattern
            })
        }
        if ($StatusF) { $view = @($view | Where-Object { $_.Status -eq $StatusF }) }
        if ($StartF)  { $view = @($view | Where-Object { $_.StartType -eq $StartF }) }

        if ($Desc) {
            $view = @($view | Sort-Object $SortProp -Descending)
        }
        else {
            $view = @($view | Sort-Object $SortProp)
        }
        return ,$view
    }

    function Format-ServiceCell {
        param([string]$Text, [int]$Width)
        if ([string]::IsNullOrEmpty($Text)) { $Text = '' }
        if ($Text.Length -gt $Width) {
            if ($Width -le 3) { return $Text.Substring(0, $Width) }
            return $Text.Substring(0, $Width - 3) + '...'
        }
        return $Text.PadRight($Width)
    }

    $allServices = @(Get-WindowsServiceStatus)
    $sortLabel = $OrdenarPor
    $sortProperty = switch ($OrdenarPor) {
        'Nome'        { 'Name' }
        'DisplayName' { 'DisplayName' }
        'Status'      { 'Status' }
        'StartType'   { 'StartType' }
        default       { 'Name' }
    }
    $sortDesc = [bool]$Decrescente
    $searchTerm = if ($Filtro) { $Filtro } else { '' }
    $statusFilter = if ($FiltroStatus) { $FiltroStatus } else { '' }
    $startFilter = if ($FiltroInicio) { $FiltroInicio } else { '' }

    $useInteractive = $Interativo -or (
        -not $PSBoundParameters.ContainsKey('Top') -and
        -not $PSBoundParameters.ContainsKey('GerarHtml') -and
        [Environment]::UserInteractive
    )

    if ($useInteractive) {
        $consoleHeight = 30
        $consoleWidth = 100
        try {
            $consoleHeight = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Height)
            $consoleWidth = [Math]::Max(80, $Host.UI.RawUI.WindowSize.Width)
        } catch { Write-Verbose "Nao foi possivel obter as dimensoes do console: $($_.Exception.Message)" }

        $headerLines = 9
        $footerLines = 5
        $pageSize = [Math]::Max(5, $consoleHeight - $headerLines - $footerLines)
        if ($PSBoundParameters.ContainsKey('Top')) {
            $pageSize = [Math]::Max(5, [Math]::Min($Top, 100))
        }

        $currentPage = 0
        $selectedRow = 0
        $needsRedraw = $true
        $statusMsg = ''
        $exitList = $false

        $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
            -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc

        while (-not $exitList) {
            if ($needsRedraw) {
                $totalCount = $filteredServices.Count
                $totalPages = [Math]::Max(1, [Math]::Ceiling([double]$totalCount / $pageSize))
                if ($currentPage -ge $totalPages) { $currentPage = $totalPages - 1 }
                if ($currentPage -lt 0) { $currentPage = 0 }

                $offset = $currentPage * $pageSize
                $pageItems = @($filteredServices | Select-Object -Skip $offset -First $pageSize)
                if ($pageItems.Count -eq 0) {
                    $selectedRow = 0
                }
                elseif ($selectedRow -ge $pageItems.Count) {
                    $selectedRow = $pageItems.Count - 1
                }
                if ($selectedRow -lt 0) { $selectedRow = 0 }

                $runCount = @($filteredServices | Where-Object { $_.Status -eq 'Running' }).Count
                $stopCount = @($filteredServices | Where-Object { $_.Status -eq 'Stopped' }).Count
                $autoStopCount = @($filteredServices | Where-Object {
                    $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic'
                }).Count

                $nameW = 28
                $dispW = [Math]::Max(20, $consoleWidth - $nameW - 30)
                $statusW = 12
                $startW = 12
                $lineW = [Math]::Min($consoleWidth - 2, $nameW + $dispW + $statusW + $startW + 6)

                $filterParts = @()
                if ($searchTerm) { $filterParts += "Busca=$searchTerm" }
                if ($statusFilter) { $filterParts += "Status=$statusFilter" }
                if ($startFilter) { $filterParts += "Inicio=$startFilter" }
                $filterStr = if ($filterParts.Count -gt 0) {
                    ($filterParts -join ' | ')
                } else {
                    'sem filtro'
                }
                $sortDirLabel = if ($sortDesc) { 'DESC' } else { 'ASC' }
                $fromIdx = if ($totalCount -eq 0) { 0 } else { $offset + 1 }
                $toIdx = [Math]::Min($offset + $pageSize, $totalCount)

                Clear-Host
                Write-Host ''
                Write-Host ('=' * $lineW) -ForegroundColor DarkCyan
                Write-Host ' SERVICOS WINDOWS' -NoNewline -ForegroundColor Cyan
                Write-Host "  |  Total: $($allServices.Count)" -NoNewline -ForegroundColor White
                Write-Host "  |  Visiveis: $totalCount" -NoNewline -ForegroundColor White
                Write-Host "  |  Exec: $runCount" -NoNewline -ForegroundColor Green
                Write-Host "  |  Parados: $stopCount" -NoNewline -ForegroundColor Yellow
                if ($autoStopCount -gt 0) {
                    Write-Host "  |  Auto-parados: $autoStopCount" -NoNewline -ForegroundColor Red
                }
                Write-Host ''
                Write-Host ('=' * $lineW) -ForegroundColor DarkCyan
                Write-Host " Filtro: $filterStr" -ForegroundColor DarkGray
                Write-Host " Ordenar: $sortLabel $sortDirLabel  |  Pagina $($currentPage + 1)/$totalPages  |  Itens $fromIdx-$toIdx de $totalCount  |  Linhas/pag: $pageSize" -ForegroundColor DarkGray
                Write-Host ('-' * $lineW) -ForegroundColor DarkGray
                Write-Host (
                    ' {0} {1} {2} {3}' -f
                    (Format-ServiceCell '#' 3),
                    (Format-ServiceCell 'NOME' $nameW),
                    (Format-ServiceCell 'DISPLAYNAME' $dispW),
                    (Format-ServiceCell 'STATUS' $statusW)
                ) -NoNewline -ForegroundColor White
                Write-Host (' ' + (Format-ServiceCell 'INICIO' $startW)) -ForegroundColor White
                Write-Host ('-' * $lineW) -ForegroundColor DarkGray

                if ($pageItems.Count -eq 0) {
                    Write-Host '  Nenhum servico encontrado com os filtros atuais.' -ForegroundColor Yellow
                }
                else {
                    for ($i = 0; $i -lt $pageItems.Count; $i++) {
                        $s = $pageItems[$i]
                        $rowNum = $offset + $i + 1
                        $isSelected = ($i -eq $selectedRow)
                        $statusColor = switch ($s.Status) {
                            'Running'      { 'Green' }
                            'Stopped'      { 'Yellow' }
                            'Paused'       { 'Red' }
                            'StartPending' { 'DarkYellow' }
                            'StopPending'  { 'DarkYellow' }
                            default        { 'Gray' }
                        }
                        $prefix = if ($isSelected) { '>' } else { ' ' }
                        $rowBg = if ($isSelected) { 'DarkBlue' } else { $null }

                        $lineName = Format-ServiceCell $s.Name $nameW
                        $lineDisp = Format-ServiceCell $s.DisplayName $dispW
                        $lineStat = Format-ServiceCell $s.Status $statusW
                        $lineStart = Format-ServiceCell $s.StartType $startW
                        $numCell = Format-ServiceCell $rowNum.ToString() 3

                        if ($isSelected) {
                            Write-Host ("$prefix$numCell $lineName $lineDisp ") -NoNewline -ForegroundColor White -BackgroundColor DarkBlue
                            Write-Host $lineStat -NoNewline -ForegroundColor $statusColor -BackgroundColor DarkBlue
                            Write-Host (" $lineStart") -ForegroundColor Cyan -BackgroundColor DarkBlue
                        }
                        else {
                            Write-Host ("$prefix$numCell ") -NoNewline -ForegroundColor DarkGray
                            Write-Host ("$lineName ") -NoNewline -ForegroundColor White
                            Write-Host ("$lineDisp ") -NoNewline -ForegroundColor Gray
                            Write-Host $lineStat -NoNewline -ForegroundColor $statusColor
                            Write-Host (" $lineStart") -ForegroundColor DarkGray
                        }
                    }
                }

                Write-Host ('-' * $lineW) -ForegroundColor DarkGray
                Write-Host ' Setas: mover/paginar  |  Home/End: 1a/ultima  |  PgUp/PgDn: pagina  |  Enter: detalhar' -ForegroundColor DarkCyan
                Write-Host ' [/]buscar  [O]rdenar  [I]nverter  [S]tatus  [F]inicio  [T]amanho  [G]o pagina  [C]lear  [R]efresh  [Q]sair' -ForegroundColor DarkCyan
                if ($statusMsg) {
                    Write-Host " $statusMsg" -ForegroundColor Yellow
                    $statusMsg = ''
                }
                $needsRedraw = $false
            }

            $key = [Console]::ReadKey($true)
            $handled = $true

            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedRow -gt 0) {
                        $selectedRow--
                    }
                    elseif ($currentPage -gt 0) {
                        $currentPage--
                        $selectedRow = $pageSize - 1
                    }
                    $needsRedraw = $true
                }
                'DownArrow' {
                    $pageItemsCount = @($filteredServices | Select-Object -Skip ($currentPage * $pageSize) -First $pageSize).Count
                    if ($selectedRow -lt ($pageItemsCount - 1)) {
                        $selectedRow++
                    }
                    else {
                        $tp = [Math]::Max(1, [Math]::Ceiling([double]$filteredServices.Count / $pageSize))
                        if ($currentPage -lt ($tp - 1)) {
                            $currentPage++
                            $selectedRow = 0
                        }
                    }
                    $needsRedraw = $true
                }
                'LeftArrow' {
                    if ($currentPage -gt 0) {
                        $currentPage--
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                }
                'RightArrow' {
                    $tp = [Math]::Max(1, [Math]::Ceiling([double]$filteredServices.Count / $pageSize))
                    if ($currentPage -lt ($tp - 1)) {
                        $currentPage++
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                }
                'PageUp' {
                    if ($currentPage -gt 0) {
                        $currentPage--
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                }
                'PageDown' {
                    $tp = [Math]::Max(1, [Math]::Ceiling([double]$filteredServices.Count / $pageSize))
                    if ($currentPage -lt ($tp - 1)) {
                        $currentPage++
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                }
                'Home' {
                    $currentPage = 0
                    $selectedRow = 0
                    $needsRedraw = $true
                }
                'End' {
                    $tp = [Math]::Max(1, [Math]::Ceiling([double]$filteredServices.Count / $pageSize))
                    $currentPage = $tp - 1
                    $selectedRow = 0
                    $needsRedraw = $true
                }
                'Enter' {
                    $pageItemsNow = @($filteredServices | Select-Object -Skip ($currentPage * $pageSize) -First $pageSize)
                    if ($pageItemsNow.Count -gt 0 -and $selectedRow -lt $pageItemsNow.Count) {
                        $sel = $pageItemsNow[$selectedRow]
                        Clear-Host
                        Write-Section "Detalhe: $($sel.Name)"
                        $detail = Get-WindowsServiceDetail -Name $sel.Name
                        if (-not $detail.Success) {
                            Write-Fail $detail.Message
                        }
                        else {
                            $statusColor = switch ($detail.Status) {
                                'Running' { 'Green' }
                                'Stopped' { 'Yellow' }
                                default   { 'Red' }
                            }
                            Write-Host ""
                            Write-Host "  Nome:          $($detail.Name)" -ForegroundColor Cyan
                            Write-Host "  Display:       $($detail.DisplayName)"
                            Write-Host "  Status:        " -NoNewline
                            Write-Host "$($detail.Status)" -ForegroundColor $statusColor
                            Write-Host "  Inicializacao: $($detail.StartType)"
                            Write-Host "  Conta:         $($detail.Account)"
                            Write-Host "  PID:           $($detail.ProcessId)"
                            Write-Host "  Caminho:       $($detail.Path)"
                            Write-Host "  Descricao:     $($detail.Description)"
                            if ($detail.DependentCount -gt 0) {
                                Write-Host "  Depende de:    $($detail.DependentServices -join ', ')" -ForegroundColor DarkGray
                            }
                            if ($detail.RequiredCount -gt 0) {
                                Write-Host "  Requer:        $($detail.RequiredServices -join ', ')" -ForegroundColor DarkGray
                            }
                        }
                        Write-Host ""
                        Write-Host '  Pressione qualquer tecla para voltar a lista...' -ForegroundColor DarkCyan
                        [Console]::ReadKey($true) | Out-Null
                        $needsRedraw = $true
                    }
                }
                'Escape' {
                    $exitList = $true
                }
                default {
                    $handled = $false
                }
            }

            if ((-not $handled) -and (-not $exitList)) {
                $char = $key.KeyChar.ToString().ToUpperInvariant()
                switch ($char) {
                    { $_ -in @('/', 'B') } {
                        Write-Host ''
                        $search = Read-Host '  Buscar (nome/display; * e ? ok; vazio=limpar)'
                        $searchTerm = if ($null -eq $search) { '' } else { $search.Trim() }
                        $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
                            -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc
                        $currentPage = 0
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                    'O' {
                        Write-Host ''
                        Write-Host '  Ordenar: [1] Nome  [2] DisplayName  [3] Status  [4] StartType' -ForegroundColor Cyan
                        $oKey = [Console]::ReadKey($true)
                        $newLabel = switch ($oKey.KeyChar.ToString()) {
                            '1' { 'Nome' }
                            '2' { 'DisplayName' }
                            '3' { 'Status' }
                            '4' { 'StartType' }
                            default { $null }
                        }
                        if ($newLabel) {
                            $sortLabel = $newLabel
                            $sortProperty = switch ($sortLabel) {
                                'Nome'        { 'Name' }
                                'DisplayName' { 'DisplayName' }
                                'Status'      { 'Status' }
                                'StartType'   { 'StartType' }
                            }
                            $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
                                -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc
                            $currentPage = 0
                            $selectedRow = 0
                        }
                        $needsRedraw = $true
                    }
                    'I' {
                        $sortDesc = -not $sortDesc
                        $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
                            -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc
                        $currentPage = 0
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                    'S' {
                        Write-Host ''
                        Write-Host '  Status: [R]unning  [P]arado  [A]paused  [T]odos' -ForegroundColor Cyan
                        $sKey = [Console]::ReadKey($true)
                        $statusFilter = switch ($sKey.KeyChar.ToString().ToUpperInvariant()) {
                            'R' { 'Running' }
                            'P' { 'Stopped' }
                            'A' { 'Paused' }
                            'T' { '' }
                            default { $statusFilter }
                        }
                        $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
                            -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc
                        $currentPage = 0
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                    'F' {
                        Write-Host ''
                        Write-Host '  Inicio: [A]utomatic  [M]anual  [D]isabled  [T]odos' -ForegroundColor Cyan
                        $fKey = [Console]::ReadKey($true)
                        $startFilter = switch ($fKey.KeyChar.ToString().ToUpperInvariant()) {
                            'A' { 'Automatic' }
                            'M' { 'Manual' }
                            'D' { 'Disabled' }
                            'T' { '' }
                            default { $startFilter }
                        }
                        $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
                            -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc
                        $currentPage = 0
                        $selectedRow = 0
                        $needsRedraw = $true
                    }
                    'T' {
                        Write-Host ''
                        $sizeInput = Read-Host "  Itens por pagina (5-100, atual: $pageSize)"
                        if ($sizeInput -match '^\d+$') {
                            $n = [int]$sizeInput
                            if ($n -ge 5 -and $n -le 100) {
                                $pageSize = $n
                                $currentPage = 0
                                $selectedRow = 0
                            }
                            else {
                                $statusMsg = 'Tamanho invalido (use 5-100).'
                            }
                        }
                        $needsRedraw = $true
                    }
                    'G' {
                        Write-Host ''
                        $tp = [Math]::Max(1, [Math]::Ceiling([double]$filteredServices.Count / $pageSize))
                        $goInput = Read-Host "  Ir para pagina (1-$tp)"
                        if ($goInput -match '^\d+$') {
                            $go = [int]$goInput
                            if ($go -ge 1 -and $go -le $tp) {
                                $currentPage = $go - 1
                                $selectedRow = 0
                            }
                            else {
                                $statusMsg = "Pagina invalida (1-$tp)."
                            }
                        }
                        $needsRedraw = $true
                    }
                    'C' {
                        $searchTerm = ''
                        $statusFilter = ''
                        $startFilter = ''
                        $filteredServices = Get-ServiceListView -Source $allServices -Search '' `
                            -StatusF '' -StartF '' -SortProp $sortProperty -Desc $sortDesc
                        $currentPage = 0
                        $selectedRow = 0
                        $statusMsg = 'Filtros limpos. Todos os servicos.'
                        $needsRedraw = $true
                    }
                    'R' {
                        $allServices = @(Get-WindowsServiceStatus)
                        $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
                            -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc
                        $currentPage = 0
                        $selectedRow = 0
                        $statusMsg = "Atualizado: $($allServices.Count) servicos."
                        $needsRedraw = $true
                    }
                    'Q' {
                        $exitList = $true
                    }
                }
            }
        }

        Clear-Host
        Write-Ok 'Listagem de servicos encerrada.'
    }
    else {
        Write-Section 'Servicos Windows'
        $filteredServices = Get-ServiceListView -Source $allServices -Search $searchTerm `
            -StatusF $statusFilter -StartF $startFilter -SortProp $sortProperty -Desc $sortDesc

        $running = @($filteredServices | Where-Object { $_.Status -eq 'Running' })
        $stopped = @($filteredServices | Where-Object { $_.Status -eq 'Stopped' })

        Write-Host ''
        Write-Host "  Total: $($allServices.Count) | Filtrados: $($filteredServices.Count) | Exec: $($running.Count) | Parados: $($stopped.Count)" -ForegroundColor Cyan
        Write-Host ''
        Write-Host ("  {0,-35} {1,-30} {2,-12} {3,-12}" -f 'NOME', 'DISPLAYNAME', 'STATUS', 'INICIO') -ForegroundColor White
        Write-Host "  $(('─' * 78))" -ForegroundColor DarkGray

        $displayServices = @($filteredServices | Select-Object -First $Top)
        foreach ($s in $displayServices) {
            $statusColor = switch ($s.Status) {
                'Running'      { 'Green' }
                'Stopped'      { 'Yellow' }
                'Paused'       { 'Red' }
                'StartPending' { 'DarkYellow' }
                default        { 'Gray' }
            }
            Write-Host ("  {0,-35}" -f (Format-ServiceCell $s.Name 35)) -NoNewline
            Write-Host ("{0,-30}" -f (Format-ServiceCell $s.DisplayName 30)) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,-12}" -f $s.Status) -NoNewline -ForegroundColor $statusColor
            Write-Host ("{0,-12}" -f $s.StartType) -ForegroundColor DarkGray
        }

        if ($filteredServices.Count -gt $Top) {
            Write-Host ''
            Write-Host "    ... e mais $($filteredServices.Count - $Top) (use -Interativo para navegar todos)" -ForegroundColor DarkGray
        }
    }
}

# ── Detalhar ───────────────────────────────────────────────────────────────

if ($Acao -eq 'Detalhar') {
    Write-Section "Detalhe: $Servico"

    $detail = Get-WindowsServiceDetail -Name $Servico

    if (-not $detail.Success) {
        Write-Fail $detail.Message
    }
    else {
        Write-Host ""
        $statusColor = switch ($detail.Status) {
            'Running' { 'Green' }
            'Stopped' { 'Yellow' }
            default   { 'Red' }
        }
        Write-Host "  Nome:         $($detail.Name)" -ForegroundColor Cyan
        Write-Host "  Display:      $($detail.DisplayName)"
        Write-Host "  Status:       " -NoNewline
        Write-Host "$($detail.Status)" -ForegroundColor $statusColor
        Write-Host "  Inicializacao:$($detail.StartType)"
        Write-Host "  Conta:        $($detail.Account)"
        Write-Host "  PID:          $($detail.ProcessId)"
        Write-Host "  Caminho:      $($detail.Path)"
        Write-Host "  Descricao:    $($detail.Description)"

        if ($detail.DependentCount -gt 0) {
            Write-Host "  Depende de:   $($detail.DependentServices -join ', ')" -ForegroundColor DarkGray
        }
        if ($detail.RequiredCount -gt 0) {
            Write-Host "  Requer:       $($detail.RequiredServices -join ', ')" -ForegroundColor DarkGray
        }
    }
}

# ── Acoes de CRUD ──────────────────────────────────────────────────────────

switch ($Acao) {
    'Iniciar' {
        Write-Section "Iniciando: $Servico"
        if ($DryRun) {
            Write-Warn "DRY-RUN: Start-Service $Servico"
        }
        else {
            $result = Start-WindowsService -Name $Servico
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'Parar' {
        Write-Section "Parando: $Servico"
        if ($DryRun) {
            Write-Warn "DRY-RUN: Stop-Service $Servico"
        }
        else {
            $result = Stop-WindowsService -Name $Servico
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'Reiniciar' {
        Write-Section "Reiniciando: $Servico"
        if ($DryRun) {
            Write-Warn "DRY-RUN: Stop-Service $Servico; Start-Service $Servico"
        }
        else {
            $result = Restart-WindowsService -Name $Servico
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'ConfigurarInicializacao' {
        Write-Section "Configurando inicializacao: $Servico -> $StartupType"
        if ($DryRun) {
            Write-Warn "DRY-RUN: Set-Service $Servico -StartupType $StartupType"
        }
        else {
            $result = Set-WindowsServiceStartup -Name $Servico -StartupType $StartupType
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }

    'ConfigurarConta' {
        Write-Section "Configurando conta: $Servico -> $Conta"
        if ($DryRun) {
            Write-Warn "DRY-RUN: Change $Servico StartName=$Conta"
        }
        else {
            $params = @{ Name = $Servico; Account = $Conta }
            if ($Credencial) { $params['Credential'] = $Credencial }
            $result = Set-WindowsServiceAccount @params
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Fail $result.Message }
        }
    }
}

# ── Relatorios ─────────────────────────────────────────────────────────────

$jsonReport = $null
$htmlReport = $null

if ($Acao -in @('Diagnostico', 'Listar', 'Detalhar')) {
    $reportData = switch ($Acao) {
        'Diagnostico' { if ($script:DiagnosticoResult) { $script:DiagnosticoResult } else { Invoke-ServiceManager -Acao Diagnostico } }
        'Listar'      { @(Get-WindowsServiceStatus) }
        'Detalhar'    { Get-WindowsServiceDetail -Name $Servico }
    }

    $jsonPath = Join-Path $ReportSession.Path "servicos-$($Acao.ToLower()).json"
    $reportData | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $jsonReport = $jsonPath
    Write-Host ""
    Write-Ok "Relatorio: $jsonPath"

    if ($GerarHtml) {
        $htmlPath = Join-Path $ReportSession.Path "servicos-$($Acao.ToLower()).html"

        $bodyHtml = switch ($Acao) {
            'Diagnostico' {
                $diag = $reportData
                $autoStopped = @($diag.StoppedAuto)
                @"
<div class="cards">
<div class="card" style="border-left-color:#16a34a"><div class="card-icon">&#9654;</div><div class="card-label">Executando</div><div class="card-value" style="color:#16a34a">$($diag.RunningCount)</div></div>
<div class="card" style="border-left-color:#d97706"><div class="card-icon">&#9724;</div><div class="card-label">Auto Parados</div><div class="card-value" style="color:#d97706">$($autoStopped.Count)</div></div>
<div class="card" style="border-left-color:#dc2626"><div class="card-icon">&#10006;</div><div class="card-label">Desabilitados</div><div class="card-value" style="color:#dc2626">$($diag.DisabledCount)</div></div>
</div>

$(if ($autoStopped.Count -gt 0) {
@"
<div class="section" style="margin-bottom:1rem">
<div class="section-hdr" style="background-color:#d97706">&#9888; Servicos Automaticos Parados ($($autoStopped.Count))</div>
<div class="section-body" style="padding:0">
<table class="data-table">
<thead><tr><th>Nome</th><th>DisplayName</th><th>Status</th></tr></thead>
<tbody>
$($autoStopped | Sort-Object Name | ForEach-Object {
    "<tr><td class=`"mono`">$($_.Name)</td><td>$($_.DisplayName)</td><td><span class=`"badge badge-yellow`">$($_.Status)</span></td></tr>"
} | Out-String)
</tbody>
</table>
</div>
</div>
"@
} else {
@"
<div class="alert" style="background-color:#d4edda;border-color:#16a34a;color:#166534">&#10004; Todos os servicos automaticos estao em execucao.</div>
"@
})
"@
            }

            'Listar' {
                $all = $reportData
                $running = @($all | Where-Object { $_.Status -eq 'Running' })
                $stopped = @($all | Where-Object { $_.Status -eq 'Stopped' })
                $other   = @($all | Where-Object { $_.Status -notin @('Running', 'Stopped') })
                $autoStopped = @($all | Where-Object { $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic' })
                $disabled = @($all | Where-Object { $_.StartType -eq 'Disabled' })
                $manual = @($all | Where-Object { $_.StartType -eq 'Manual' })
                @"
<div class="cards">
<div class="card"><div class="card-icon">&#128202;</div><div class="card-label">Total</div><div class="card-value">$($all.Count)</div></div>
<div class="card" style="border-left-color:#16a34a"><div class="card-icon">&#9654;</div><div class="card-label">Executando</div><div class="card-value" style="color:#16a34a">$($running.Count)</div></div>
<div class="card" style="border-left-color:#d97706"><div class="card-icon">&#9724;</div><div class="card-label">Parados</div><div class="card-value" style="color:#d97706">$($stopped.Count)</div></div>
<div class="card" style="border-left-color:#dc2626"><div class="card-icon">&#10006;</div><div class="card-label">Desabilitados</div><div class="card-value" style="color:#dc2626">$($disabled.Count)</div></div>
</div>

<div class="section" style="margin-bottom:1rem">
<div class="section-hdr">&#128203; Servicos por Status</div>
<div class="section-body" style="padding:0">
<table class="data-table">
<thead><tr><th>Status</th><th>Quantidade</th><th>%</th></tr></thead>
<tbody>
<tr><td><span class="badge badge-green">Running</span></td><td>$($running.Count)</td><td>$([Math]::Round($running.Count / $all.Count * 100, 1))%</td></tr>
<tr><td><span class="badge badge-yellow">Stopped</span></td><td>$($stopped.Count)</td><td>$([Math]::Round($stopped.Count / $all.Count * 100, 1))%</td></tr>
$(if ($other.Count -gt 0) { "<tr><td><span class=`"badge badge-blue`">Outros</span></td><td>$($other.Count)</td><td>$([Math]::Round($other.Count / $all.Count * 100, 1))%</td></tr>" })
</tbody>
</table>
</div>
</div>

<div class="section" style="margin-bottom:1rem">
<div class="section-hdr">&#9881; Servicos por Inicializacao</div>
<div class="section-body" style="padding:0">
<table class="data-table">
<thead><tr><th>Tipo</th><th>Quantidade</th><th>%</th></tr></thead>
<tbody>
<tr><td><span class="badge badge-green">Automatic</span></td><td>$(@($all | Where-Object { $_.StartType -eq 'Automatic' }).Count)</td><td>$([Math]::Round(@($all | Where-Object { $_.StartType -eq 'Automatic' }).Count / $all.Count * 100, 1))%</td></tr>
<tr><td><span class="badge badge-yellow">Manual</span></td><td>$($manual.Count)</td><td>$([Math]::Round($manual.Count / $all.Count * 100, 1))%</td></tr>
<tr><td><span class="badge badge-red">Disabled</span></td><td>$($disabled.Count)</td><td>$([Math]::Round($disabled.Count / $all.Count * 100, 1))%</td></tr>
</tbody>
</table>
</div>
</div>

$(if ($autoStopped.Count -gt 0) {
@"
<div class="section" style="margin-bottom:1rem">
<div class="section-hdr" style="background-color:#d97706">&#9888; Servicos Automaticos Parados ($($autoStopped.Count))</div>
<div class="section-body" style="padding:0">
<table class="data-table">
<thead><tr><th>Nome</th><th>DisplayName</th><th>Status</th></tr></thead>
<tbody>
$($autoStopped | Sort-Object Name | ForEach-Object {
    "<tr><td class=`"mono`">$($_.Name)</td><td>$($_.DisplayName)</td><td><span class=`"badge badge-yellow`">$($_.Status)</span></td></tr>"
} | Out-String)
</tbody>
</table>
</div>
</div>
"@
})

<div class="section">
<div class="section-hdr">&#128203; Todos os Servicos ($($all.Count))</div>
<div class="section-body" style="padding:0">
<table class="data-table">
<thead><tr><th>Nome</th><th>DisplayName</th><th>Status</th><th>StartType</th></tr></thead>
<tbody>
$($all | Sort-Object Name | ForEach-Object {
    $sc = switch ($_.Status) { 'Running' { 'badge-green' } 'Stopped' { 'badge-yellow' } default { 'badge-gray' } }
    "<tr><td class=`"mono`">$($_.Name)</td><td>$($_.DisplayName)</td><td><span class=`"badge $sc`">$($_.Status)</span></td><td>$($_.StartType)</td></tr>"
} | Out-String)
</tbody>
</table>
</div>
</div>
"@
            }

            'Detalhar' {
                $d = $reportData
                $sc = switch ($d.Status) { 'Running' { 'badge-green' } 'Stopped' { 'badge-yellow' } default { 'badge-red' } }
                $ic = switch ($d.StartType) { 'Automatic' { 'badge-green' } 'Manual' { 'badge-yellow' } 'Disabled' { 'badge-red' } default { 'badge-gray' } }
                @"
<div class="section" style="margin-bottom:1rem">
<div class="section-hdr">&#128269; Detalhe: $($d.Name)</div>
<div class="section-body" style="padding:0">
<table class="kv-table">
<tr><td>Nome</td><td class="mono">$($d.Name)</td></tr>
<tr><td>DisplayName</td><td>$($d.DisplayName)</td></tr>
<tr><td>Status</td><td><span class="badge $sc">$($d.Status)</span></td></tr>
<tr><td>Inicializacao</td><td><span class="badge $ic">$($d.StartType)</span></td></tr>
<tr><td>Conta</td><td class="mono">$($d.Account)</td></tr>
<tr><td>PID</td><td>$($d.ProcessId)</td></tr>
<tr><td>Caminho</td><td class="mono" style="word-break:break-all">$($d.Path)</td></tr>
<tr><td>Descricao</td><td>$($d.Description)</td></tr>
</table>
</div>
</div>

$(if ($d.DependentCount -gt 0) {
@"
<div class="section" style="margin-bottom:1rem">
<div class="section-hdr">&#128279; Servicos que dependem de $($d.Name) ($($d.DependentCount))</div>
<div class="section-body">
<ul>$($d.DependentServices | ForEach-Object { "<li class=`"mono`">$_</li>" } | Out-String)</ul>
</div>
</div>
"@
})

$(if ($d.RequiredCount -gt 0) {
@"
<div class="section">
<div class="section-hdr">&#128279; Servicos requeridos por $($d.Name) ($($d.RequiredCount))</div>
<div class="section-body">
<ul>$($d.RequiredServices | ForEach-Object { "<li class=`"mono`">$_</li>" } | Out-String)</ul>
</div>
</div>
"@
})
"@
            }
        }

        $html = New-ToolkitHtmlReport -Title "Gerenciamento de Servicos" `
            -Subtitle "$Acao - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            -Icon "&#9881;" -Body $bodyHtml -FooterText "Gerado por WBA Windows Toolkit"
        [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($true))
        $htmlReport = $htmlPath
        Write-Ok "HTML: $htmlPath"
    }
}

if ($AbrirRelatorio) {
    $target = if ($htmlReport) { $htmlReport } elseif ($jsonReport) { $jsonReport } else { $null }
    if ($target -and (Test-Path -LiteralPath $target)) { Start-Process $target }
}

if ($transcriptActive) { Stop-Transcript }

Write-Host ""
Write-Ok "Gerenciamento de servicos concluido."
