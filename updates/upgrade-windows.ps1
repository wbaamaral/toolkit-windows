#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $false)]
param(
    [ValidateSet('Auto', 'WinGet', 'Chocolatey', 'All')]
    [string]$Backend = 'Auto',

    [ValidateSet('UpgradeAll', 'ListOnly', 'Select')]
    [string]$Action = 'UpgradeAll',

    [switch]$NoWinGet,
    [switch]$NoChocolatey,
    [switch]$NoWindowsUpdate,
    [switch]$SaveBackendPreference,
    [switch]$NonInteractive,
    [switch]$Help,
    [switch]$Version,

    [Alias('DiretorioSaida')]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

chcp 65001 | Out-Null

$ToolkitRoot      = Split-Path -Parent $PSScriptRoot
$ToolkitModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $ToolkitModulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Updates; Manual=Atualização geral do Windows com backend resolvido

<#
.SINOPSE
    Atualização geral do Windows com suporte a múltiplos backends.

.DESCRIÇÃO
    Executa uma rotina de atualização geral com backend resolvido automaticamente ou
    definido pelo operador. Suporta WinGet, Chocolatey e Windows Update como etapa final.

    O backend padrão é Auto: resolve WinGet ou Chocolatey conforme o ambiente e
    a disponibilidade. Windows Update é executado por último em UpgradeAll.

    O script nunca reinicia automaticamente a máquina.

.PARÂMETROS
    -Backend          Backend de pacotes: Auto (padrão), WinGet, Chocolatey, All.
    -Action           Ação: UpgradeAll (padrão), ListOnly, Select.
    -NoWinGet         Impede uso do WinGet.
    -NoChocolatey     Impede uso do Chocolatey.
    -NoWindowsUpdate  Impede execução do Windows Update (apenas esta execução).
    -SaveBackendPreference  Salva o backend resolvido como preferência persistente.
    -NonInteractive   Modo não interativo. Falha em configuração inválida em vez de perguntar.
    -Help             Exibe ajuda.
    -Version          Exibe versão.
    -Path             Raiz de relatórios. Padrão: configuração global ou C:\WBA\Relatorios.

.FORMA DE USO
    Set-ExecutionPolicy Bypass -Scope Process -Force

    .\upgrade-windows.ps1
    .\upgrade-windows.ps1 -Backend WinGet
    .\upgrade-windows.ps1 -Backend WinGet -Action ListOnly
    .\upgrade-windows.ps1 -Backend Chocolatey -NoWindowsUpdate
    .\upgrade-windows.ps1 -Backend All -Action UpgradeAll
    .\upgrade-windows.ps1 -NoWindowsUpdate

.OBSERVAÇÃO
    Salve este arquivo como UTF-8 BOM para uso com o Windows PowerShell 5.1.
#>

$ScriptVersion = 'v2.0-upgrade-backends'

$ScriptName = if ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name }
              else { Split-Path -Leaf $PSCommandPath }
$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

# ---------------------------------------------------------------------------
# Validacao de parametros
# ---------------------------------------------------------------------------

function Assert-UpgradeParameters {
    [CmdletBinding()]
    param(
        [string]$Backend      = 'Auto',
        [switch]$NoWinGet,
        [switch]$NoChocolatey,
        [switch]$NoWindowsUpdate
    )

    if ($Backend -eq 'WinGet' -and $NoWinGet) {
        throw "Combinacao invalida: -Backend WinGet nao pode ser usado com -NoWinGet."
    }
    if ($Backend -eq 'Chocolatey' -and $NoChocolatey) {
        throw "Combinacao invalida: -Backend Chocolatey nao pode ser usado com -NoChocolatey."
    }
    if ($Backend -eq 'All' -and $NoWinGet -and $NoChocolatey -and $NoWindowsUpdate) {
        throw "Combinacao invalida: -Backend All com -NoWinGet, -NoChocolatey e -NoWindowsUpdate elimina todas as acoes possiveis."
    }
}

# ---------------------------------------------------------------------------
# Deteccao de backend
# ---------------------------------------------------------------------------

function Test-BackendAvailable {
    [CmdletBinding()]
    param(
        [ValidateSet('WinGet', 'Chocolatey')]
        [string]$Backend
    )

    $exe = switch ($Backend) {
        'WinGet'     { 'winget.exe' }
        'Chocolatey' { 'choco.exe' }
    }
    return [bool](Get-Command $exe -ErrorAction SilentlyContinue)
}

function Get-PreferredBackendForEnvironment {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { return 'WinGet' }
    $caption = $os.Caption
    if ($caption -match 'Server 2016|Server 2019|Server 2022') { return 'Chocolatey' }
    return 'WinGet'
}

function Resolve-UpgradeBackend {
    [CmdletBinding()]
    param(
        [string]$Backend      = 'Auto',
        [switch]$NoWinGet,
        [switch]$NoChocolatey
    )

    if ($Backend -eq 'WinGet') {
        if (-not (Test-BackendAvailable -Backend 'WinGet')) {
            throw "Backend WinGet solicitado mas nao encontrado no sistema."
        }
        return [PSCustomObject]@{ Backend = 'WinGet'; Reason = 'Backend WinGet solicitado explicitamente.' }
    }

    if ($Backend -eq 'Chocolatey') {
        if (-not (Test-BackendAvailable -Backend 'Chocolatey')) {
            throw "Backend Chocolatey solicitado mas nao encontrado no sistema."
        }
        return [PSCustomObject]@{ Backend = 'Chocolatey'; Reason = 'Backend Chocolatey solicitado explicitamente.' }
    }

    if ($Backend -eq 'All') {
        $useWinGet  = (-not $NoWinGet)  -and (Test-BackendAvailable -Backend 'WinGet')
        $useChoco   = (-not $NoChocolatey) -and (Test-BackendAvailable -Backend 'Chocolatey')

        if ($useWinGet -and $useChoco) {
            return [PSCustomObject]@{ Backend = 'All'; Reason = 'Backend All solicitado com WinGet e Chocolatey disponiveis.' }
        }
        if ($useWinGet) {
            return [PSCustomObject]@{ Backend = 'WinGet'; Reason = 'Backend All solicitado; Chocolatey bloqueado ou ausente.' }
        }
        if ($useChoco) {
            return [PSCustomObject]@{ Backend = 'Chocolatey'; Reason = 'Backend All solicitado; WinGet bloqueado ou ausente.' }
        }
        return [PSCustomObject]@{ Backend = 'None'; Reason = 'Backend All solicitado mas nenhum backend disponivel.' }
    }

    # Auto
    $preferred  = Get-PreferredBackendForEnvironment
    $secondary  = if ($preferred -eq 'WinGet') { 'Chocolatey' } else { 'WinGet' }

    $tryFirst   = $preferred
    $trySecond  = $secondary

    if ($NoWinGet -and $tryFirst -eq 'WinGet') {
        $tryFirst  = $secondary
        $trySecond = $null
    }
    if ($NoChocolatey -and $tryFirst -eq 'Chocolatey') {
        $tryFirst  = $secondary
        $trySecond = $null
    }

    foreach ($candidate in @($tryFirst, $trySecond) | Where-Object { $_ }) {
        if ($NoWinGet     -and $candidate -eq 'WinGet')     { continue }
        if ($NoChocolatey -and $candidate -eq 'Chocolatey') { continue }
        if (Test-BackendAvailable -Backend $candidate) {
            $reason = "Backend Auto: $candidate selecionado (preferido para este ambiente)."
            if ($candidate -ne $preferred) {
                $reason = "Backend Auto: $candidate selecionado como alternativa ($preferred indisponivel ou bloqueado)."
            }
            return [PSCustomObject]@{ Backend = $candidate; Reason = $reason }
        }
    }

    return [PSCustomObject]@{ Backend = 'None'; Reason = 'Backend Auto: nenhum backend de pacotes disponivel.' }
}

# ---------------------------------------------------------------------------
# Reboot pendente
# ---------------------------------------------------------------------------

function Test-RegistryPathExists {
    [CmdletBinding()]
    param([string]$Path)
    return (Test-Path $Path)
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    )
    foreach ($key in $keys) {
        if (Test-RegistryPathExists -Path $key) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# WinGet
# ---------------------------------------------------------------------------

function Invoke-WinGetList {
    $raw = winget upgrade --include-unknown 2>&1
    $updates = [System.Collections.Generic.List[PSCustomObject]]::new()
    $inTable = $false
    foreach ($line in $raw) {
        if ($line -match '^-{10,}') { $inTable = $true; continue }
        if (-not $inTable)          { continue }
        if ($line -match '^\s*$')   { continue }
        if ($line -match '(\d+)\s+upgrade(s?) available') { continue }
        $parts = $line -split '\s{2,}'
        if ($parts.Count -ge 4) {
            $updates.Add([PSCustomObject]@{
                Name             = $parts[0].Trim()
                Id               = $parts[1].Trim()
                CurrentVersion   = $parts[2].Trim()
                AvailableVersion = $parts[3].Trim()
            })
        }
    }
    return $updates.ToArray()
}

function Invoke-ProcessWithSpinner {
    param(
        [string]  $Label,
        [string]  $FilePath,
        [string[]]$ArgumentList
    )
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $frames = '|', '/', '-', '\'
    $i      = 0
    try {
        $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr `
            -NoNewWindow -PassThru -ErrorAction Stop

        while (-not $proc.HasExited) {
            Write-Host "`r$($frames[$i % 4]) $Label" -NoNewline -ForegroundColor Cyan
            $i++
            Start-Sleep -Milliseconds 200
        }
        $proc.WaitForExit()
        Write-Host ("`r" + (' ' * ($Label.Length + 4)) + "`r") -NoNewline

        $out = Get-Content -LiteralPath $tmpOut -ErrorAction SilentlyContinue
        $err = Get-Content -LiteralPath $tmpErr -ErrorAction SilentlyContinue
        if ($out) { $out | Out-Host }
        if ($err) { $err | Out-Host }

        return $proc.ExitCode
    }
    catch {
        Write-Host ("`r" + (' ' * ($Label.Length + 4)) + "`r") -NoNewline
        throw
    }
    finally {
        Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WinGetUpgrade {
    $result = [PSCustomObject]@{ Success = $false; Partial = $false; ExitCode = 0; Message = '' }
    try {
        $exitCode = Invoke-ProcessWithSpinner -Label 'WinGet: trabalhando...' -FilePath 'winget' `
            -ArgumentList @('upgrade', '--all', '--include-unknown', '--silent',
                '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        $result.ExitCode = $exitCode
        $result.Success  = ($exitCode -eq 0 -or $exitCode -eq 3010)
        $result.Partial  = ($exitCode -ne 0 -and $exitCode -ne 3010)
        $result.Message  = if ($result.Success) { 'WinGet: upgrade concluido.' } else { "WinGet: exit code $exitCode." }
    }
    catch {
        $result.Message = "WinGet: excecao — $($_.Exception.Message)"
    }
    return $result
}

function Invoke-WinGetUpgradePackage {
    [CmdletBinding()]
    param([string]$PackageId)

    $result = [PSCustomObject]@{ PackageId = $PackageId; Success = $false; ExitCode = 0; Message = '' }
    try {
        $exitCode = Invoke-ProcessWithSpinner -Label "WinGet: atualizando $PackageId..." -FilePath 'winget' `
            -ArgumentList @('upgrade', '--id', $PackageId, '--silent',
                '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        $result.ExitCode = $exitCode
        $result.Success  = ($exitCode -eq 0 -or $exitCode -eq 3010)
        $result.Message  = if ($result.Success) { "WinGet: $PackageId atualizado." } else { "WinGet: $PackageId exit code $exitCode." }
    }
    catch {
        $result.Message = "WinGet: $PackageId excecao — $($_.Exception.Message)"
    }
    return $result
}

# ---------------------------------------------------------------------------
# Chocolatey
# ---------------------------------------------------------------------------

function Invoke-ChocolateyList {
    $raw = choco outdated --no-progress 2>&1
    $updates = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($line in $raw) {
        if ($line -match '^Chocolatey v') { continue }
        $parts = $line -split '\|'
        if ($parts.Count -ge 3) {
            $updates.Add([PSCustomObject]@{
                Id               = $parts[0].Trim()
                Name             = $parts[0].Trim()
                CurrentVersion   = $parts[1].Trim()
                AvailableVersion = $parts[2].Trim()
            })
        }
    }
    return $updates.ToArray()
}

function Invoke-ChocolateyUpgrade {
    $result = [PSCustomObject]@{ Success = $false; Partial = $false; ExitCode = 0; Message = '' }
    try {
        $exitCode = Invoke-ProcessWithSpinner -Label 'Chocolatey: trabalhando...' -FilePath 'choco' `
            -ArgumentList @('upgrade', 'all', '-y', '--no-progress')
        $result.ExitCode = $exitCode
        $result.Success  = ($exitCode -eq 0)
        $result.Partial  = ($exitCode -ne 0)
        $result.Message  = if ($result.Success) { 'Chocolatey: upgrade concluido.' } else { "Chocolatey: exit code $exitCode." }
    }
    catch {
        $result.Message = "Chocolatey: excecao — $($_.Exception.Message)"
    }
    return $result
}

function Invoke-ChocolateyUpgradePackage {
    [CmdletBinding()]
    param([string]$PackageId)

    $result = [PSCustomObject]@{ PackageId = $PackageId; Success = $false; ExitCode = 0; Message = '' }
    try {
        $exitCode = Invoke-ProcessWithSpinner -Label "Chocolatey: atualizando $PackageId..." -FilePath 'choco' `
            -ArgumentList @('upgrade', $PackageId, '-y', '--no-progress')
        $result.ExitCode = $exitCode
        $result.Success  = ($exitCode -eq 0)
        $result.Message  = if ($result.Success) { "Choco: $PackageId atualizado." } else { "Choco: $PackageId exit code $exitCode." }
    }
    catch {
        $result.Message = "Choco: $PackageId excecao — $($_.Exception.Message)"
    }
    return $result
}

# ---------------------------------------------------------------------------
# Windows Update
# ---------------------------------------------------------------------------

function Invoke-WindowsUpdateStep {
    $result = [PSCustomObject]@{ Success = $false; Skipped = $false; ExitCode = 0; Message = '' }

    $usoClient = Get-Command UsoClient.exe -ErrorAction SilentlyContinue
    if (-not $usoClient) {
        $result.Message = 'UsoClient.exe nao encontrado. Windows Update nao pode ser acionado.'
        return $result
    }

    try {
        Write-Info 'Acionando varredura do Windows Update...'
        UsoClient.exe StartScan
        Start-Sleep -Seconds 2
        UsoClient.exe StartDownload
        Start-Sleep -Seconds 2
        UsoClient.exe StartInstall
        $result.Success = $true
        $result.Message = 'Windows Update acionado via UsoClient. Verificar progresso em Configuracoes > Windows Update.'
    }
    catch {
        $result.Message = "Windows Update: excecao — $($_.Exception.Message)"
    }
    return $result
}

# ---------------------------------------------------------------------------
# Codigo de saida
# ---------------------------------------------------------------------------

function Get-UpgradeExitCode {
    [CmdletBinding()]
    param(
        [bool]$BackendSuccess        = $true,
        [bool]$BackendPartialFailure = $false,
        [bool]$WUSuccess             = $true,
        [bool]$WUSkipped             = $false,
        [bool]$RebootPending         = $false,
        [bool]$ParameterError        = $false,
        [bool]$BackendUnavailable    = $false,
        [bool]$Cancelled             = $false
    )

    if ($ParameterError)        { return 8 }
    if ($BackendUnavailable)    { return 2 }
    if ($Cancelled)             { return 9 }
    if ($BackendPartialFailure) { return 4 }
    if (-not $BackendSuccess)   { return 5 }
    if (-not $WUSkipped -and -not $WUSuccess) { return 6 }
    if ($RebootPending)         { return 7 }
    return 0
}

# ---------------------------------------------------------------------------
# Selecao de pacotes (interativo)
# ---------------------------------------------------------------------------

function Read-PackageSelection {
    [CmdletBinding()]
    param(
        [PSCustomObject[]]$Packages,
        [switch]$NonInteractive
    )

    if (-not $Packages -or $Packages.Count -eq 0) {
        Write-Info 'Nenhuma atualizacao disponivel.'
        return @()
    }

    Write-Section 'Atualizacoes disponíveis'
    for ($i = 0; $i -lt $Packages.Count; $i++) {
        $pkg = $Packages[$i]
        Write-Host "  [$($i + 1)] $($pkg.Name) — $($pkg.CurrentVersion) -> $($pkg.AvailableVersion)"
    }
    Write-Host ''

    if ($NonInteractive) {
        Write-Warn 'Modo nao interativo: selecao cancelada automaticamente.'
        return @()
    }

    $input = Read-Host 'Digite os numeros separados por virgula (ou ENTER para cancelar)'
    if ([string]::IsNullOrWhiteSpace($input)) { return @() }

    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($part in $input -split ',') {
        $idx = 0
        if ([int]::TryParse($part.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $Packages.Count) {
            $selected.Add($Packages[$idx - 1].Id)
        }
    }
    return $selected.ToArray()
}

# ---------------------------------------------------------------------------
# Resumo final
# ---------------------------------------------------------------------------

function Show-UpgradeSummary {
    [CmdletBinding()]
    param([PSCustomObject]$Summary)

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' Resumo da manutencao' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    Write-Host ''
    Write-Host 'Parametros:' -ForegroundColor Yellow
    Write-Host "    Backend solicitado : $($Summary.Backend)"
    Write-Host "    Action             : $($Summary.Action)"
    Write-Host "    NoWindowsUpdate    : $(if ($Summary.NoWindowsUpdate) { 'Sim' } else { 'Nao' })"

    if ($Summary.PSObject.Properties['Resolution']) {
        Write-Host ''
        Write-Host 'Backend:' -ForegroundColor Yellow
        Write-Host "    Backend resolvido  : $($Summary.Resolution.Backend)"
        Write-Host "    Motivo             : $($Summary.Resolution.Reason)"
    }

    if ($Summary.PSObject.Properties['BackendResult'] -and $Summary.BackendResult) {
        Write-Host ''
        $backendLabel = if ($Summary.PSObject.Properties['Resolution'] -and $Summary.Resolution) { $Summary.Resolution.Backend } else { 'Backend' }
        Write-Host "${backendLabel}:" -ForegroundColor Yellow
        $br = $Summary.BackendResult
        $status = if ($br.Success) { 'Concluido' } elseif ($br.Partial) { 'Falha parcial' } else { 'Falha total' }
        Write-Host "    Status             : $status"
        Write-Host "    ExitCode           : $($br.ExitCode)"
        if ($br.PSObject.Properties['Message'] -and $br.Message) { Write-Host "    Mensagem           : $($br.Message)" }
    }

    if ($Summary.PSObject.Properties['WUResult'] -and $Summary.WUResult) {
        Write-Host ''
        Write-Host 'Windows Update:' -ForegroundColor Yellow
        $wr = $Summary.WUResult
        if ($wr.Skipped) {
            Write-Host '    Status             : Ignorado via -NoWindowsUpdate'
        }
        else {
            $wuStatus = if ($wr.Success) { 'Acionado' } else { 'Falha' }
            Write-Host "    Status             : $wuStatus"
            if ($wr.PSObject.Properties['Message'] -and $wr.Message) { Write-Host "    Mensagem           : $($wr.Message)" }
        }
    }

    Write-Host ''
    Write-Host 'Reboot:' -ForegroundColor Yellow
    $rBefore = if ($Summary.RebootPendingBefore) { 'Sim' } else { 'Nao' }
    $rAfter  = if ($Summary.RebootPendingAfter)  { 'Sim' } else { 'Nao' }
    Write-Host "    Pendente antes     : $rBefore"
    Write-Host "    Pendente apos      : $rAfter"

    Write-Host ''
    Write-Host 'Resultado final:' -ForegroundColor Yellow
    $exitMsg = switch ($Summary.ExitCode) {
        0  { 'Concluido sem falhas e sem reboot pendente.' }
        2  { 'Backend solicitado nao disponivel.' }
        3  { 'Falha de pre-condicao.' }
        4  { 'Falha parcial na atualizacao.' }
        5  { 'Falha total no backend.' }
        6  { 'Falha no Windows Update.' }
        7  { 'Concluido com reboot pendente.' }
        8  { 'Parametros invalidos.' }
        9  { 'Cancelado pelo operador.' }
        default { "Codigo de saida: $($Summary.ExitCode)" }
    }
    $color = if ($Summary.ExitCode -eq 0) { 'Green' } elseif ($Summary.ExitCode -eq 7) { 'Yellow' } else { 'Red' }
    Write-Host "    $exitMsg" -ForegroundColor $color
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Fluxos de acao
# ---------------------------------------------------------------------------

function Invoke-ListOnly {
    [CmdletBinding()]
    param(
        [string]$ResolvedBackend
    )

    Write-Section "Listagem de atualizacoes — $ResolvedBackend"

    switch ($ResolvedBackend) {
        'WinGet' {
            $packages = @(Invoke-WinGetList)
            if ($packages.Count -eq 0) {
                Write-Info 'Nenhuma atualizacao disponivel no WinGet.'
            }
            else {
                Write-Info "$($packages.Count) atualizacoes disponiveis:"
                foreach ($pkg in $packages) {
                    Write-Host "  $($pkg.Name) [$($pkg.Id)] $($pkg.CurrentVersion) -> $($pkg.AvailableVersion)"
                }
            }
        }
        'Chocolatey' {
            $packages = @(Invoke-ChocolateyList)
            if ($packages.Count -eq 0) {
                Write-Info 'Nenhuma atualizacao disponivel no Chocolatey.'
            }
            else {
                Write-Info "$($packages.Count) atualizacoes disponiveis:"
                foreach ($pkg in $packages) {
                    Write-Host "  $($pkg.Name) $($pkg.CurrentVersion) -> $($pkg.AvailableVersion)"
                }
            }
        }
        'All' {
            Write-Info 'Listando WinGet...'
            Invoke-ListOnly -ResolvedBackend 'WinGet'
            Write-Info 'Listando Chocolatey...'
            Invoke-ListOnly -ResolvedBackend 'Chocolatey'
        }
        default {
            Write-Warn "Backend '$ResolvedBackend' nao suporta listagem."
        }
    }
}

function Invoke-SelectUpgrade {
    [CmdletBinding()]
    param(
        [string]$ResolvedBackend,
        [switch]$NonInteractive
    )

    Write-Section "Atualizacao seletiva — $ResolvedBackend"

    switch ($ResolvedBackend) {
        'WinGet' {
            $packages   = @(Invoke-WinGetList)
            $selectedIds = @(Read-PackageSelection -Packages $packages -NonInteractive:$NonInteractive)
            if ($selectedIds.Count -eq 0) {
                Write-Info 'Nenhum pacote selecionado. Operacao cancelada.'
                return [PSCustomObject]@{ Success = $true; Cancelled = $true; Results = @() }
            }
            $results = foreach ($id in $selectedIds) { Invoke-WinGetUpgradePackage -PackageId $id }
            return [PSCustomObject]@{ Success = $true; Cancelled = $false; Results = @($results) }
        }
        'Chocolatey' {
            $packages   = @(Invoke-ChocolateyList)
            $selectedIds = @(Read-PackageSelection -Packages $packages -NonInteractive:$NonInteractive)
            if ($selectedIds.Count -eq 0) {
                Write-Info 'Nenhum pacote selecionado. Operacao cancelada.'
                return [PSCustomObject]@{ Success = $true; Cancelled = $true; Results = @() }
            }
            $results = foreach ($id in $selectedIds) { Invoke-ChocolateyUpgradePackage -PackageId $id }
            return [PSCustomObject]@{ Success = $true; Cancelled = $false; Results = @($results) }
        }
        default {
            throw "Backend '$ResolvedBackend' nao suportado para Select."
        }
    }
}

function Invoke-UpgradeAll {
    [CmdletBinding()]
    param(
        [string]$ResolvedBackend,
        [switch]$NoWindowsUpdate,
        [switch]$NoWinGet,
        [switch]$NoChocolatey
    )

    if ($ResolvedBackend -eq 'None' -and $NoWindowsUpdate) {
        throw "Nenhum backend de pacotes disponivel e -NoWindowsUpdate informado. Nenhuma acao possivel."
    }

    $rebootBefore = Test-PendingReboot
    if ($rebootBefore) {
        Write-Warn 'Reboot pendente detectado antes da execucao. Algumas atualizacoes podem falhar.'
    }

    $backendResult = $null

    switch ($ResolvedBackend) {
        'WinGet' {
            Write-Section 'WinGet — upgrade geral'
            $backendResult = Invoke-WinGetUpgrade
        }
        'Chocolatey' {
            Write-Section 'Chocolatey — upgrade geral'
            $backendResult = Invoke-ChocolateyUpgrade
        }
        'All' {
            Write-Section 'WinGet — upgrade geral'
            $wgResult = Invoke-WinGetUpgrade
            Write-Section 'Chocolatey — upgrade geral'
            $chResult = Invoke-ChocolateyUpgrade
            $wgMsg = if ($null -ne $wgResult -and $wgResult.PSObject.Properties['Message']) { $wgResult.Message } else { '' }
            $chMsg = if ($null -ne $chResult -and $chResult.PSObject.Properties['Message']) { $chResult.Message } else { '' }
            $backendResult = [PSCustomObject]@{
                Success  = $wgResult.Success -and $chResult.Success
                Partial  = $wgResult.Partial -or $chResult.Partial
                ExitCode = [Math]::Max($wgResult.ExitCode, $chResult.ExitCode)
                Message  = "WinGet: $wgMsg | Chocolatey: $chMsg"
                WinGet      = $wgResult
                Chocolatey  = $chResult
            }
        }
        'None' {
            Write-Warn 'Nenhum backend de pacotes disponivel. Prosseguindo apenas com Windows Update.'
            $backendResult = [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0; Message = 'Nenhum backend de pacotes utilizado.' }
        }
    }

    $wuResult = $null
    if ($NoWindowsUpdate) {
        $wuResult = [PSCustomObject]@{ Success = $true; Skipped = $true; ExitCode = 0; Message = 'Ignorado via -NoWindowsUpdate.' }
    }
    else {
        Write-Section 'Windows Update'
        $wuResult = Invoke-WindowsUpdateStep
    }

    $rebootAfter = Test-PendingReboot

    return [PSCustomObject]@{
        BackendResult      = $backendResult
        WUResult           = $wuResult
        RebootPendingBefore = $rebootBefore
        RebootPendingAfter  = $rebootAfter
    }
}

# ---------------------------------------------------------------------------
# Orquestrador principal
# ---------------------------------------------------------------------------

function Show-Help {
    Write-Host ''
    Write-Host 'Atualização geral do Windows — backend resolvido' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Uso:' -ForegroundColor Yellow
    Write-Host "  .\$ScriptName [opcoes]"
    Write-Host ''
    Write-Host 'Parametros:' -ForegroundColor Yellow
    Write-Host '  -Backend <Auto|WinGet|Chocolatey|All>   Backend de pacotes (padrao: Auto)'
    Write-Host '  -Action <UpgradeAll|ListOnly|Select>    Acao (padrao: UpgradeAll)'
    Write-Host '  -NoWinGet                               Impede uso do WinGet'
    Write-Host '  -NoChocolatey                           Impede uso do Chocolatey'
    Write-Host '  -NoWindowsUpdate                        Impede execucao do Windows Update'
    Write-Host '  -SaveBackendPreference                  Salva backend como preferencia'
    Write-Host '  -NonInteractive                         Modo nao interativo'
    Write-Host '  -Help                                   Esta ajuda'
    Write-Host '  -Version                                Versao do script'
    Write-Host '  -Path                                   Raiz de relatorios'
    Write-Host ''
    Write-Host 'Exemplos:' -ForegroundColor Yellow
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Backend WinGet"
    Write-Host "  .\$ScriptName -Backend WinGet -Action ListOnly"
    Write-Host "  .\$ScriptName -Backend Chocolatey -NoWindowsUpdate"
    Write-Host "  .\$ScriptName -Backend All"
    Write-Host "  .\$ScriptName -NoWindowsUpdate"
    Write-Host ''
}

function Invoke-UpgradeMain {
    [CmdletBinding()]
    param(
        [string]$Backend,
        [string]$Action,
        [switch]$NoWinGet,
        [switch]$NoChocolatey,
        [switch]$NoWindowsUpdate,
        [switch]$SaveBackendPreference,
        [switch]$NonInteractive,
        [string]$Path
    )

    $exitCode = 0

    try {
        Assert-UpgradeParameters `
            -Backend $Backend `
            -NoWinGet:$NoWinGet `
            -NoChocolatey:$NoChocolatey `
            -NoWindowsUpdate:$NoWindowsUpdate
    }
    catch {
        Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
        exit 8
    }

    $ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'Updates'
    $LogDir  = $ReportSession.LogsPath
    $LogFile = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-upgrade-windows.log"

    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    $transcriptActive = $false
    try {
        Start-Transcript -Path $LogFile -Append -ErrorAction Stop
        $transcriptActive = $true
    }
    catch {
        Write-Warn "Nao foi possivel iniciar transcricao: $($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host " Upgrade do Windows — $ScriptVersion" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Script  : $ScriptName" -ForegroundColor Yellow
    Write-Host "Backend : $Backend | Action: $Action" -ForegroundColor Yellow
    Write-Host "Log     : $LogFile" -ForegroundColor Yellow

    $resolution = $null
    try {
        $resolution = Resolve-UpgradeBackend -Backend $Backend -NoWinGet:$NoWinGet -NoChocolatey:$NoChocolatey
        Write-Info "Backend resolvido: $($resolution.Backend) — $($resolution.Reason)"
    }
    catch {
        Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 2
    }

    $summary = [PSCustomObject]@{
        Backend          = $Backend
        Action           = $Action
        NoWindowsUpdate  = $NoWindowsUpdate.IsPresent
        Resolution       = $resolution
        BackendResult    = $null
        WUResult         = $null
        RebootPendingBefore = $false
        RebootPendingAfter  = $false
        ExitCode         = 0
    }

    switch ($Action) {
        'ListOnly' {
            Invoke-ListOnly -ResolvedBackend $resolution.Backend
            $summary.ExitCode = 0
        }
        'Select' {
            $selectResult = Invoke-SelectUpgrade -ResolvedBackend $resolution.Backend -NonInteractive:$NonInteractive
            if ($selectResult.Cancelled) {
                $summary.ExitCode = 9
            }
            else {
                $anyFail = ($selectResult.Results | Where-Object { -not $_.Success }).Count -gt 0
                $summary.ExitCode = if ($anyFail) { 4 } else { 0 }
            }
        }
        'UpgradeAll' {
            try {
                $upgradeResult = Invoke-UpgradeAll `
                    -ResolvedBackend $resolution.Backend `
                    -NoWindowsUpdate:$NoWindowsUpdate `
                    -NoWinGet:$NoWinGet `
                    -NoChocolatey:$NoChocolatey

                $summary.BackendResult      = $upgradeResult.BackendResult
                $summary.WUResult           = $upgradeResult.WUResult
                $summary.RebootPendingBefore = $upgradeResult.RebootPendingBefore
                $summary.RebootPendingAfter  = $upgradeResult.RebootPendingAfter

                $br = $upgradeResult.BackendResult
                $wr = $upgradeResult.WUResult

                $summary.ExitCode = Get-UpgradeExitCode `
                    -BackendSuccess        ($null -ne $br -and $br.Success) `
                    -BackendPartialFailure ($null -ne $br -and $br.Partial) `
                    -WUSuccess             ($null -ne $wr -and $wr.Success) `
                    -WUSkipped             ($null -ne $wr -and $wr.Skipped) `
                    -RebootPending         $upgradeResult.RebootPendingAfter `
                    -ParameterError        $false `
                    -BackendUnavailable    $false `
                    -Cancelled             $false
            }
            catch {
                Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
                $summary.ExitCode = 3
            }
        }
    }

    Show-UpgradeSummary -Summary $summary

    if ($transcriptActive) { Stop-Transcript }

    exit $summary.ExitCode
}

# ---------------------------------------------------------------------------
# Ponto de entrada — nao executar quando dot-sourced em testes
# ---------------------------------------------------------------------------

if (-not $env:WBA_PESTER_TESTING) {
    if ($Help) {
        Show-Help
        exit 0
    }

    if ($Version) {
        Write-Host "Script  : $ScriptName" -ForegroundColor Cyan
        Write-Host "Versao  : $ScriptVersion" -ForegroundColor Green
        exit 0
    }

    if (-not (Test-IsAdministrator)) {
        $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
            if ($kv.Value -is [switch]) {
                if ($kv.Value.IsPresent) { "-$($kv.Key)" }
            }
            else {
                "-$($kv.Key)"; "$($kv.Value)"
            }
        }
        $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"") + $relaunchArgs
        Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
        exit
    }

    Invoke-UpgradeMain `
        -Backend            $Backend `
        -Action             $Action `
        -NoWinGet:           $NoWinGet `
        -NoChocolatey:       $NoChocolatey `
        -NoWindowsUpdate:    $NoWindowsUpdate `
        -SaveBackendPreference: $SaveBackendPreference `
        -NonInteractive:     $NonInteractive `
        -Path               $Path
}
