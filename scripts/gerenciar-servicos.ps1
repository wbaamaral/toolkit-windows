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
    Filtra servicos por nome (wildcard). Ex.: 'W32*', '*网络*'.

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
    Modo interativo com scroll, busca, ordenacao e filtro para Listar.

.PARAMETER StartupType
    Tipo de inicializacao para ConfigurarInicializacao: Automatic, Manual, Disabled.

.PARAMETER Conta
    Conta de logon para ConfigurarConta. Built-in: LocalSystem, LocalService, NetworkService.

.PARAMETER Senha
    Senha da conta (necessario para contas de dominio).

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
    .\gerenciar-servicos.ps1 -Acao Listar -Filtro 'W32*' -FiltroStatus Running

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Listar -OrdenarPor Status -Decrescente -Top 20

.EXAMPLE
    .\gerenciar-servicos.ps1 -Acao Listar -Interativo

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

    [string]$Senha,

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

try { chcp 65001 | Out-Null } catch { }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $PSScriptRoot

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$actionRequiresAdmin = @('Iniciar', 'Parar', 'Reiniciar', 'ConfigurarInicializacao', 'ConfigurarConta')
if ($Acao -in $actionRequiresAdmin -and -not (Test-IsAdministrator)) {
    Write-Warning "A acao '$Acao' exige privilegios administrativos. Solicitando elevacao..."
    $command = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) -Verb RunAs
    exit 0
}

$CoreModulePath    = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$ServicesModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Services/WbaToolkit.Services.psd1'

foreach ($mod in @($CoreModulePath, $ServicesModulePath)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        exit 1
    }
}

try {
    Import-Module $CoreModulePath    -Force -ErrorAction Stop
    Import-Module $ServicesModulePath -Force -ErrorAction Stop
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos do toolkit." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
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
        Write-Host "[FALHA] Acao '$Acao' requer -Servico." -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

if ($Acao -eq 'ConfigurarInicializacao' -and [string]::IsNullOrWhiteSpace($StartupType)) {
    Write-Host "[FALHA] Acao 'ConfigurarInicializacao' requer -StartupType." -ForegroundColor Red
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

if ($Acao -eq 'ConfigurarConta' -and [string]::IsNullOrWhiteSpace($Conta)) {
    Write-Host "[FALHA] Acao 'ConfigurarConta' requer -Conta." -ForegroundColor Red
    if ($transcriptActive) { Stop-Transcript }
    exit 1
}

# ── Diagnostico ────────────────────────────────────────────────────────────

if ($Acao -eq 'Diagnostico') {
    Write-Section "Diagnostico de Servicos"

    $result = Invoke-ServiceManager -Acao Diagnostico

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
    Write-Section "Servicos Windows"

    $allServices = @(Get-WindowsServiceStatus)
    $totalAll = $allServices.Count

    $filteredServices = $allServices

    if ($Filtro) {
        $filteredServices = @($filteredServices | Where-Object { $_.Name -like $Filtro -or $_.DisplayName -like $Filtro })
    }
    if ($FiltroStatus) {
        $filteredServices = @($filteredServices | Where-Object { $_.Status -eq $FiltroStatus })
    }
    if ($FiltroInicio) {
        $filteredServices = @($filteredServices | Where-Object { $_.StartType -eq $FiltroInicio })
    }

    $sortProperty = switch ($OrdenarPor) {
        'Nome'        { 'Name' }
        'DisplayName' { 'DisplayName' }
        'Status'      { 'Status' }
        'StartType'   { 'StartType' }
    }
    if ($Decrescente) {
        $filteredServices = @($filteredServices | Sort-Object $sortProperty -Descending)
    }
    else {
        $filteredServices = @($filteredServices | Sort-Object $sortProperty)
    }

    $running = @($filteredServices | Where-Object { $_.Status -eq 'Running' })
    $stopped = @($filteredServices | Where-Object { $_.Status -eq 'Stopped' })

    Write-Host ""
    Write-Host "  Total: $totalAll servicos | Filtrados: $($filteredServices.Count)" -ForegroundColor Cyan
    Write-Host "  Em execucao: $($running.Count)" -ForegroundColor Green
    Write-Host "  Parados:     $($stopped.Count)" -ForegroundColor Yellow
    Write-Host ""

    if ($Interativo) {
        $pageSize = [Math]::Min($Top, 25)
        $currentPage = 0
        $sortLabel = $OrdenarPor
        $sortDir = if ($Decrescente) { 'DESC' } else { 'ASC' }
        $searchTerm = if ($Filtro) { $Filtro } else { '' }
        $statusFilter = if ($FiltroStatus) { $FiltroStatus } else { '' }
        $startFilter = if ($FiltroInicio) { $FiltroInicio } else { '' }

        function Show-ServicePage {
            param(
                [object[]]$Services,
                [int]$Page,
                [int]$Size,
                [string]$SortBy,
                [string]$Dir,
                [string]$Search,
                [string]$StatusF,
                [string]$StartF
            )

            $totalPages = [Math]::Max(1, [Math]::Ceiling($Services.Count / $Size))
            if ($Page -ge $totalPages) { $Page = $totalPages - 1 }
            if ($Page -lt 0) { $Page = 0 }

            $offset = $Page * $Size
            $pageItems = @($Services | Select-Object -Skip $offset -First $Size)

            $runningPage = @($pageItems | Where-Object { $_.Status -eq 'Running' }).Count
            $stoppedPage = @($pageItems | Where-Object { $_.Status -eq 'Stopped' }).Count

            $filterParts = @()
            if ($Search) { $filterParts += "Busca: $Search" }
            if ($StatusF) { $filterParts += "Status: $StatusF" }
            if ($StartF) { $filterParts += "Inicio: $StartF" }
            $filterStr = if ($filterParts.Count -gt 0) { " | $($filterParts -join ' | ')" } else { '' }

            Write-Host ""
            Write-Host "  Pagina $($Page + 1)/$totalPages | $($Services.Count) servicos | Exec: $runningPage | Parados: $stoppedPage | Ordenar: $SortBy $Dir$filterStr" -ForegroundColor Cyan
            Write-Host "  $(('─' * 78))" -ForegroundColor DarkGray
            Write-Host ("  {0,-35} {1,-30} {2,-12} {3,-12}" -f 'NOME', 'DISPLAYNAME', 'STATUS', 'INICIO') -ForegroundColor White
            Write-Host "  $(('─' * 78))" -ForegroundColor DarkGray

            foreach ($s in $pageItems) {
                $statusColor = switch ($s.Status) {
                    'Running'      { 'Green' }
                    'Stopped'      { 'Yellow' }
                    'Paused'       { 'Red' }
                    'StartPending' { 'DarkYellow' }
                    default        { 'Gray' }
                }
                $nameDisplay = if ($s.Name.Length -gt 33) { $s.Name.Substring(0, 30) + '...' } else { $s.Name }
                $dispDisplay = if ($s.DisplayName.Length -gt 28) { $s.DisplayName.Substring(0, 25) + '...' } else { $s.DisplayName }

                Write-Host ("  {0,-35}" -f $nameDisplay) -NoNewline
                Write-Host ("{0,-30}" -f $dispDisplay) -NoNewline -ForegroundColor Gray
                Write-Host ("{0,-12}" -f $s.Status) -NoNewline -ForegroundColor $statusColor
                Write-Host ("{0,-12}" -f $s.StartType) -ForegroundColor DarkGray
            }

            Write-Host ""
            Write-Host "  Comandos: [E]squerda [D]ireita [B]uscar [O]rdenar [F]iltrar [T]amanho [S]tatus [I]nicio [C]lear [R]efresh [Q]uit" -ForegroundColor DarkCyan
            Write-Host "  Pagina atual: $($Page + 1) de $totalPages" -ForegroundColor DarkGray

            return @{ Page = $Page; TotalPages = $totalPages }
        }

        $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
            -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter

        while ($true) {
            $key = [Console]::ReadKey($true)
            $char = $key.KeyChar.ToString().ToUpper()

            switch ($char) {
                'D' {
                    if ($state.Page -lt $state.TotalPages - 1) {
                        $currentPage++
                        $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                            -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                    }
                }
                'E' {
                    if ($currentPage -gt 0) {
                        $currentPage--
                        $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                            -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                    }
                }
                'B' {
                    Write-Host ""
                    $search = Read-Host "  Buscar (nome/display, *wildcard*): "
                    $searchTerm = $search
                    $filteredServices = @($allServices | Where-Object {
                        $_.Name -like "*$search*" -or $_.DisplayName -like "*$search*"
                    })
                    if ($statusFilter) { $filteredServices = @($filteredServices | Where-Object { $_.Status -eq $statusFilter }) }
                    if ($startFilter) { $filteredServices = @($filteredServices | Where-Object { $_.StartType -eq $startFilter }) }
                    $filteredServices = @($filteredServices | Sort-Object $sortProperty)
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                }
                'O' {
                    Write-Host ""
                    Write-Host "  Ordenar por: [1] Nome [2] DisplayName [3] Status [4] StartType" -ForegroundColor Cyan
                    $oKey = [Console]::ReadKey($true)
                    $sortLabel = switch ($oKey.KeyChar.ToString()) {
                        '1' { 'Nome' }
                        '2' { 'DisplayName' }
                        '3' { 'Status' }
                        '4' { 'StartType' }
                        default { $sortLabel }
                    }
                    $sortProperty = switch ($sortLabel) {
                        'Nome'        { 'Name' }
                        'DisplayName' { 'DisplayName' }
                        'Status'      { 'Status' }
                        'StartType'   { 'StartType' }
                    }
                    $filteredServices = @($filteredServices | Sort-Object $sortProperty)
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                }
                'F' {
                    Write-Host ""
                    Write-Host "  Filtrar por Inicio: [A] Automatic [M] Manual [D] Disabled [T] Todos" -ForegroundColor Cyan
                    $fKey = [Console]::ReadKey($true)
                    $startFilter = switch ($fKey.KeyChar.ToString().ToUpper()) {
                        'A' { 'Automatic' }
                        'M' { 'Manual' }
                        'D' { 'Disabled' }
                        'T' { '' }
                        default { $startFilter }
                    }
                    $filteredServices = @($allServices)
                    if ($searchTerm) { $filteredServices = @($filteredServices | Where-Object { $_.Name -like "*$searchTerm*" -or $_.DisplayName -like "*$searchTerm*" }) }
                    if ($statusFilter) { $filteredServices = @($filteredServices | Where-Object { $_.Status -eq $statusFilter }) }
                    if ($startFilter) { $filteredServices = @($filteredServices | Where-Object { $_.StartType -eq $startFilter }) }
                    $filteredServices = @($filteredServices | Sort-Object $sortProperty)
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                }
                'S' {
                    Write-Host ""
                    Write-Host "  Filtrar por Status: [R]unning [S]topped [P]aused [T]odos" -ForegroundColor Cyan
                    $sKey = [Console]::ReadKey($true)
                    $statusFilter = switch ($sKey.KeyChar.ToString().ToUpper()) {
                        'R' { 'Running' }
                        'S' { 'Stopped' }
                        'P' { 'Paused' }
                        'T' { '' }
                        default { $statusFilter }
                    }
                    $filteredServices = @($allServices)
                    if ($searchTerm) { $filteredServices = @($filteredServices | Where-Object { $_.Name -like "*$searchTerm*" -or $_.DisplayName -like "*$searchTerm*" }) }
                    if ($statusFilter) { $filteredServices = @($filteredServices | Where-Object { $_.Status -eq $statusFilter }) }
                    if ($startFilter) { $filteredServices = @($filteredServices | Where-Object { $_.StartType -eq $startFilter }) }
                    $filteredServices = @($filteredServices | Sort-Object $sortProperty)
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                }
                'I' {
                    $sortDir = if ($sortDir -eq 'ASC') { 'DESC' } else { 'ASC' }
                    if ($sortDir -eq 'DESC') {
                        $filteredServices = @($filteredServices | Sort-Object $sortProperty -Descending)
                    }
                    else {
                        $filteredServices = @($filteredServices | Sort-Object $sortProperty)
                    }
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                }
                'T' {
                    Write-Host ""
                    $sizeInput = Read-Host "  Itens por pagina (atual: $pageSize): "
                    if ($sizeInput -match '^\d+$' -and [int]$sizeInput -ge 5 -and [int]$sizeInput -le 500) {
                        $pageSize = [int]$sizeInput
                    }
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                }
                'C' {
                    $searchTerm = ''
                    $statusFilter = ''
                    $startFilter = ''
                    $filteredServices = @($allServices | Sort-Object $sortProperty)
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search '' -StatusF '' -StartF ''
                }
                'R' {
                    $allServices = @(Get-WindowsServiceStatus)
                    $filteredServices = @($allServices | Sort-Object $sortProperty)
                    $currentPage = 0
                    $state = Show-ServicePage -Services $filteredServices -Page $currentPage -Size $pageSize `
                        -SortBy $sortLabel -Dir $sortDir -Search $searchTerm -StatusF $statusFilter -StartF $startFilter
                }
                'Q' {
                    Write-Host ""
                    Write-Ok "Saindo do modo interativo."
                    break
                }
            }
        }
    }
    else {
        $displayServices = $filteredServices | Select-Object -First $Top
        Write-Host ""
        Write-Host ("  {0,-35} {1,-30} {2,-12} {3,-12}" -f 'NOME', 'DISPLAYNAME', 'STATUS', 'INICIO') -ForegroundColor White
        Write-Host "  $(('─' * 78))" -ForegroundColor DarkGray

        foreach ($s in $displayServices) {
            $statusColor = switch ($s.Status) {
                'Running'      { 'Green' }
                'Stopped'      { 'Yellow' }
                'Paused'       { 'Red' }
                'StartPending' { 'DarkYellow' }
                default        { 'Gray' }
            }
            Write-Host ("  {0,-35}" -f $s.Name) -NoNewline
            Write-Host ("{0,-30}" -f $s.DisplayName) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,-12}" -f $s.Status) -NoNewline -ForegroundColor $statusColor
            Write-Host ("{0,-12}" -f $s.StartType) -ForegroundColor DarkGray
        }

        if ($filteredServices.Count -gt $Top) {
            Write-Host ""
            Write-Host "    ... e mais $($filteredServices.Count - $Top) servicos (use -Top ou -Interativo)" -ForegroundColor DarkGray
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
            Write-Host "  DRY-RUN: Start-Service $Servico" -ForegroundColor Yellow
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
            Write-Host "  DRY-RUN: Stop-Service $Servico" -ForegroundColor Yellow
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
            Write-Host "  DRY-RUN: Stop-Service $Servico; Start-Service $Servico" -ForegroundColor Yellow
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
            Write-Host "  DRY-RUN: Set-Service $Servico -StartupType $StartupType" -ForegroundColor Yellow
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
            Write-Host "  DRY-RUN: Change $Servico StartName=$Conta" -ForegroundColor Yellow
        }
        else {
            $params = @{ Name = $Servico; Account = $Conta }
            if ($Senha) { $params['Password'] = $Senha }
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
        'Diagnostico' { Invoke-ServiceManager -Acao Diagnostico }
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
