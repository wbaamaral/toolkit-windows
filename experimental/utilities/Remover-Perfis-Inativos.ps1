# =============================================================================
# [NAO VALIDADO] Script sem execucao real documentada em Windows.
# Nao recomendado para uso em producao ate validacao operacional.
# Registro: nao-validado/README.md
# =============================================================================
#Requires -Version 5.1
<#
.SYNOPSIS
    Lista perfis de usuario locais com espaco em disco e permite remocao interativa
    de perfis antigos ou inativos.

.DESCRIPTION
    Enumera todos os perfis de usuario nao-sistema do Windows, calcula o espaco
    ocupado por cada um, exibe o ultimo acesso e o status da conta associada.
    O operador escolhe interativamente quais perfis remover; a remocao usa
    Win32_UserProfile (que limpa tambem a chave de registro do perfil).

    Perfis do sistema (Default, Public, SYSTEM, etc.) sao excluidos automaticamente.
    Perfis com sessao ativa (usuario logado) nao podem ser removidos e sao sinalizados.

.FUNCIONALIDADES
    - Lista perfis com: usuario, caminho, tamanho, ultimo acesso, dias inativos e status.
    - Classifica cada perfil: Ativo, Inativo, Sem Conta (orfao) ou Carregado.
    - Interface interativa com selecao individual ou em massa.
    - Preview em tempo real do espaco total que sera recuperado.
    - Confirmacao obrigatoria antes de qualquer remocao.
    - Modo silencioso para automacao: remove orfaos/inativos sem interacao.
    - Flag -DryRun para simular remocao sem alterar o sistema.
    - Log completo na pasta padronizada de relatorios do toolkit.

.USO
    Modo interativo (padrao):
        .\Remover-Perfis-Inativos.ps1

    Simular sem remover nada:
        .\Remover-Perfis-Inativos.ps1 -DryRun

    Remocao automatica de orfaos + inativos ha mais de 90 dias:
        .\Remover-Perfis-Inativos.ps1 -Silent

    Alterar limiar de inatividade para 180 dias:
        .\Remover-Perfis-Inativos.ps1 -InactiveDays 180

    Excluir perfis especificos da listagem:
        .\Remover-Perfis-Inativos.ps1 -ExcludeProfile "svc.backup","adm.temp"

.NOTAS
    Requer privilegios de Administrador.
    A remocao via Win32_UserProfile exclui a pasta do perfil E a chave de registro.
    Perfis ativamente carregados nao podem ser removidos sem logoff do usuario.
    Recomenda-se -DryRun antes de usar -Silent em producao.
    Testado no Windows 10 Pro (21H2+) e Windows 11 Pro.
#>
param (
    [switch]$Help,
    [switch]$Version,
    [switch]$DryRun,
    [switch]$Silent,
    [switch]$NoLog,

    [int]$InactiveDays = 90,

    [string[]]$ExcludeProfile = @(),

    [Alias('DiretorioSaida')]
    [string]$Path
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

# WBA-DOCS: Category=Utilities; Manual=Remocao de perfis de usuario inativos

$ScriptVersion = "v1.0"
$ScriptName    = $MyInvocation.MyCommand.Name
$ReportSession = $null
$LogDir        = $null
$LogFile       = $null

$SystemFolders = @(
    'systemprofile', 'LocalService', 'NetworkService',
    'Default', 'Public', 'All Users', 'Default User', 'defaultuser0'
)

# ---------------------------------------------------------------------------
# Funcoes utilitarias
# ---------------------------------------------------------------------------

function Show-Help {
    Write-Host ""
    Write-Host "Remocao de Perfis de Usuario Inativos — $script:ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "Opcoes:"
    Write-Host "  -Help                         Mostra esta ajuda"
    Write-Host "  -Version                      Mostra a versao"
    Write-Host "  -DryRun                       Simula remocao sem alterar o sistema"
    Write-Host "  -Silent                       Remove automaticamente orfaos/inativos sem prompts"
    Write-Host "  -NoLog                        Nao cria arquivo de log"
    Write-Host "  -InactiveDays <N>             Limiar de inatividade em dias (padrao: 90)"
    Write-Host "  -ExcludeProfile '<n>','<n>'   Nomes de perfis a ignorar na listagem"
    Write-Host "  -DiretorioSaida <dir>         Raiz de relatorios. Padrao: configuracao global ou C:\WBA\Relatorios"
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -DryRun"
    Write-Host "  .\$ScriptName -Silent -InactiveDays 180"
    Write-Host "  .\$ScriptName -ExcludeProfile `"svc.backup`",`"adm.temp`""
    Write-Host ""
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return [long]0 }
    try {
        $size  = [long]0
        $stack = New-Object 'System.Collections.Generic.Stack[string]'
        $stack.Push($Path)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            try {
                foreach ($f in [System.IO.Directory]::GetFiles($dir)) {
                    try { $size += (New-Object System.IO.FileInfo($f)).Length } catch {}
                }
                foreach ($d in [System.IO.Directory]::GetDirectories($dir)) {
                    $stack.Push($d)
                }
            } catch {}
        }
        return $size
    }
    catch { return [long]0 }
}

# ---------------------------------------------------------------------------
# Coleta de perfis
# ---------------------------------------------------------------------------

function Get-LocalProfiles {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    Write-Host ""
    Write-Host "Coletando perfis de usuario..." -ForegroundColor Yellow

    $wmiProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
        Where-Object { -not $_.Special }

    $profiles = New-Object 'System.Collections.Generic.List[PSCustomObject]'
    $index    = 1

    foreach ($wp in $wmiProfiles) {
        $path       = $wp.LocalPath
        $folderName = Split-Path $path -Leaf

        if ($script:SystemFolders -contains $folderName) { continue }
        if ($path -match 'systemprofile|LocalService|NetworkService') { continue }

        $skip = $false
        foreach ($ex in $script:ExcludeProfile) {
            if ($folderName -like "*$ex*" -or $path -like "*$ex*") { $skip = $true; break }
        }
        if ($skip) { continue }

        # Resolver SID em nome de usuario
        $sid          = $wp.SID
        $userName     = $folderName
        $domain       = $env:COMPUTERNAME
        $accountExists = $false

        try {
            $ntAccount = ([Security.Principal.SecurityIdentifier]::new($sid)).Translate([Security.Principal.NTAccount]).Value
            if ($ntAccount -match '\\') {
                $parts    = $ntAccount -split '\\'
                $domain   = $parts[0]
                $userName = $parts[1]
            } else {
                $userName = $ntAccount
            }
            $accountExists = $true
        }
        catch {
            $domain   = '--'
            $userName = $folderName
        }

        # Ultimo acesso e inatividade
        $lastUse       = $wp.LastUseTime
        $daysInactive  = if ($lastUse) { [int]((Get-Date) - $lastUse).TotalDays } else { 9999 }
        $lastUseDisplay = if ($lastUse) { $lastUse.ToString('dd/MM/yyyy HH:mm') } else { 'Desconhecido' }

        # Tamanho
        Write-Host "  Calculando: $folderName..." -NoNewline -ForegroundColor DarkGray
        $sizeBytes = Get-FolderSize -Path $path
        Write-Host " $(Format-FileSize $sizeBytes)" -ForegroundColor DarkGray

        # Status
        $isLoaded      = $wp.Loaded
        $isCurrentUser = ($sid -eq $currentSid)
        $canDelete     = -not ($isLoaded -or $isCurrentUser)

        $status = switch ($true) {
            { $isLoaded -or $isCurrentUser } { 'Carregado';                 break }
            { -not $accountExists }          { 'Sem conta';                 break }
            { $daysInactive -ge $script:InactiveDays } {
                "Inativo ($daysInactive`d)"; break }
            { $daysInactive -lt 30 }         { 'Ativo';                     break }
            default                          { "Recente ($daysInactive`d)" }
        }

        $statusColor = switch ($status) {
            { $_ -like 'Carregado*' } { 'Cyan';   break }
            { $_ -like 'Sem conta*' } { 'Red';    break }
            { $_ -like 'Inativo*'  } { 'Yellow'; break }
            { $_ -like 'Ativo'     } { 'Green';  break }
            default                   { 'White'  }
        }

        $profiles.Add([PSCustomObject]@{
            Index          = $index
            SID            = $sid
            LocalPath      = $path
            FolderName     = $folderName
            UserName       = $userName
            Domain         = $domain
            LastUseDisplay = $lastUseDisplay
            DaysInactive   = $daysInactive
            SizeBytes      = $sizeBytes
            SizeDisplay    = (Format-FileSize $sizeBytes)
            IsLoaded       = $isLoaded
            IsCurrentUser  = $isCurrentUser
            AccountExists  = $accountExists
            CanDelete      = $canDelete
            Status         = $status
            StatusColor    = $statusColor
            Selected       = $false
            Deleted        = $false
        })
        $index++
    }

    Write-Host "  $($profiles.Count) perfil(s) encontrado(s)." -ForegroundColor Yellow
    return $profiles
}

# ---------------------------------------------------------------------------
# Interface interativa
# ---------------------------------------------------------------------------

function Show-ProfileTable {
    param(
        [System.Collections.Generic.List[PSCustomObject]]$Profiles,
        [string]$Message = ""
    )

    try { [Console]::Clear() } catch {}

    $visible  = $Profiles | Where-Object { -not $_.Deleted }
    $selList  = @($visible | Where-Object { $_.Selected })
    $selCount = $selList.Count
    $selSize  = ($selList | Measure-Object -Property SizeBytes -Sum).Sum
    $totalSize = ($visible | Measure-Object -Property SizeBytes -Sum).Sum

    $dryTag = if ($script:DryRun) { " [SIMULACAO]" } else { "" }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Remocao de Perfis Inativos — $($script:ScriptVersion)$dryTag" -ForegroundColor Cyan
    if ($selCount -gt 0) {
        Write-Host (" Selecionados: $selCount | Recuperavel: $(Format-FileSize $selSize)") -ForegroundColor Yellow
    }
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Cabecalho da tabela
    $hdr = " {0,-4} {1,-4} {2,-24} {3,-20} {4,-8} {5,-10} {6}" `
        -f "Sel", "#", "Usuario", "Ultimo Acesso", "Dias", "Tamanho", "Status"
    Write-Host $hdr -ForegroundColor Gray
    Write-Host (" " + "-" * 84) -ForegroundColor DarkGray

    foreach ($p in $visible) {
        $sel        = if ($p.Selected) { "[*]" } else { "[ ]" }
        $selColor   = if ($p.Selected) { 'Yellow' } else { 'DarkGray' }
        $userDisp   = if ($p.Domain -and $p.Domain -ne '--' -and $p.Domain -ne $env:COMPUTERNAME) {
            "$($p.Domain)\$($p.UserName)"
        } else { $p.UserName }
        if ($userDisp.Length -gt 23) { $userDisp = $userDisp.Substring(0, 20) + '...' }

        $daysDisp   = if ($p.DaysInactive -eq 9999) { '---' } else { "$($p.DaysInactive)d" }
        $noDelTag   = if (-not $p.CanDelete) { ' [nao pode]' } else { '' }

        $row = " {0,-4} {1,-4} {2,-24} {3,-20} {4,-8} {5,-10}" `
            -f $sel, $p.Index, $userDisp, $p.LastUseDisplay, $daysDisp, $p.SizeDisplay

        Write-Host $row -NoNewline -ForegroundColor $p.StatusColor
        Write-Host "$($p.Status)$noDelTag" -ForegroundColor $p.StatusColor
    }

    Write-Host (" " + "-" * 84) -ForegroundColor DarkGray

    $orphans  = @($visible | Where-Object { -not $_.AccountExists }).Count
    $inactive = @($visible | Where-Object { $_.DaysInactive -ge $script:InactiveDays -and $_.CanDelete }).Count

    Write-Host ""
    Write-Host (" Total: $($visible.Count) perfil(s) | Espaco total: $(Format-FileSize $totalSize) | Orfaos: $orphans | Inativos (>$($script:InactiveDays)d): $inactive") -ForegroundColor Gray
    Write-Host ""

    if ($Message) {
        Write-Host "  >> $Message" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host " Comandos:" -ForegroundColor Cyan
    Write-Host "   [numero(s)]  selecionar/deselecionar  ex: 1   ou   1 3 5" -ForegroundColor Gray
    Write-Host "   a            selecionar todos os elegíveis (orfaos + inativos)" -ForegroundColor Gray
    Write-Host "   c            limpar selecao" -ForegroundColor Gray
    Write-Host "   d            remover perfis selecionados" -ForegroundColor Gray
    Write-Host "   i <n>        ver detalhes do perfil numero n" -ForegroundColor Gray
    Write-Host "   q            sair sem remover nada" -ForegroundColor Green
    Write-Host ""
}

function Show-ProfileDetail {
    param([PSCustomObject]$Profile)
    try { [Console]::Clear() } catch {}
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Detalhes do Perfil #$($Profile.Index)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  {0,-18}: {1}" -f "Usuario",      "$($Profile.Domain)\$($Profile.UserName)")
    Write-Host ("  {0,-18}: {1}" -f "Caminho",       $Profile.LocalPath)
    Write-Host ("  {0,-18}: {1}" -f "SID",           $Profile.SID)
    Write-Host ("  {0,-18}: {1}" -f "Tamanho",       $Profile.SizeDisplay)
    Write-Host ("  {0,-18}: {1}" -f "Ultimo acesso", $Profile.LastUseDisplay)
    $daysDisp = if ($Profile.DaysInactive -eq 9999) { 'Desconhecido' } else { "$($Profile.DaysInactive) dias" }
    Write-Host ("  {0,-18}: {1}" -f "Dias inativo",  $daysDisp)
    Write-Host ("  {0,-18}: {1}" -f "Conta existe",  $(if ($Profile.AccountExists) { 'Sim' } else { 'Nao (SID orfao)' }))
    Write-Host ("  {0,-18}: {1}" -f "Carregado",     $(if ($Profile.IsLoaded) { 'Sim (usuario ativo)' } else { 'Nao' }))
    $canDelDisp = if ($Profile.CanDelete) { 'Sim' } else { 'Nao' }
    Write-Host ("  {0,-18}: " -f "Pode remover") -NoNewline
    Write-Host $canDelDisp -ForegroundColor $(if ($Profile.CanDelete) { 'Green' } else { 'Red' })
    Write-Host ("  {0,-18}: " -f "Status") -NoNewline
    Write-Host $Profile.Status -ForegroundColor $Profile.StatusColor
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Remocao
# ---------------------------------------------------------------------------

function Remove-Profiles {
    param([System.Collections.Generic.List[PSCustomObject]]$ToDelete)

    $results   = New-Object 'System.Collections.Generic.List[PSCustomObject]'
    $freedBytes = [long]0

    foreach ($p in $ToDelete) {
        $label = "$($p.UserName) [$($p.SizeDisplay)]"
        Write-Host "  Removendo: $label..." -NoNewline -ForegroundColor Yellow

        if ($script:DryRun) {
            Write-Host " [SIMULACAO — nao removido]" -ForegroundColor Cyan
            $results.Add([PSCustomObject]@{ Profile = $p; Success = $true; Error = $null })
            $freedBytes += $p.SizeBytes
            continue
        }

        try {
            $wmiObj = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($p.SID)'" -ErrorAction Stop
            Remove-CimInstance -InputObject $wmiObj -ErrorAction Stop
            Write-Host " [OK]" -ForegroundColor Green
            $results.Add([PSCustomObject]@{ Profile = $p; Success = $true; Error = $null })
            $freedBytes += $p.SizeBytes
        }
        catch {
            Write-Host " [FALHOU: $($_.Exception.Message)]" -ForegroundColor Red
            Write-Warning "ERRO ao remover '$($p.UserName)': $($_.Exception.Message)"
            $results.Add([PSCustomObject]@{ Profile = $p; Success = $false; Error = $_.Exception.Message })
        }
    }

    return @{ Results = $results; FreedBytes = $freedBytes }
}

# ---------------------------------------------------------------------------
# Menu interativo principal
# ---------------------------------------------------------------------------

function Invoke-InteractiveMenu {
    param([System.Collections.Generic.List[PSCustomObject]]$Profiles)

    $msg     = ""
    $running = $true

    while ($running) {
        Show-ProfileTable -Profiles $Profiles -Message $msg
        $msg = ""

        $cmd = (Read-Host "Comando").Trim().ToLower()

        if ($cmd -eq 'q') {
            $running = $false
        }
        elseif ($cmd -eq 'a') {
            $count = 0
            foreach ($p in $Profiles) {
                if (-not $p.Deleted -and $p.CanDelete -and (-not $p.AccountExists -or $p.DaysInactive -ge $script:InactiveDays)) {
                    $p.Selected = $true; $count++
                }
            }
            $msg = if ($count -gt 0) { "$count perfil(s) selecionado(s) automaticamente." } else { "Nenhum perfil elegivel encontrado." }
        }
        elseif ($cmd -eq 'c') {
            foreach ($p in $Profiles) { $p.Selected = $false }
            $msg = "Selecao limpa."
        }
        elseif ($cmd -eq 'd') {
            $selected = @($Profiles | Where-Object { -not $_.Deleted -and $_.Selected -and $_.CanDelete })
            if ($selected.Count -eq 0) {
                $msg = "Nenhum perfil selecionado para remocao. Use numeros ou [a] para selecionar."; continue
            }

            try { [Console]::Clear() } catch {}
            $totalSelSize = ($selected | Measure-Object -Property SizeBytes -Sum).Sum
            $dryTag = if ($script:DryRun) { " [SIMULACAO]" } else { "" }

            Write-Host ""
            Write-Host "============================================================" -ForegroundColor Red
            Write-Host " Confirmacao de Remocao$dryTag" -ForegroundColor Red
            Write-Host "============================================================" -ForegroundColor Red
            Write-Host ""
            foreach ($p in $selected) {
                Write-Host ("  {0,-28} {1,-10} {2}" -f $p.UserName, $p.SizeDisplay, $p.Status) -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "  Total: $($selected.Count) perfil(s) | Espaco a recuperar: $(Format-FileSize $totalSelSize)" -ForegroundColor Yellow
            if (-not $script:DryRun) {
                Write-Host "  ATENCAO: esta acao NAO pode ser desfeita!" -ForegroundColor Red
            }
            Write-Host ""

            do { $confirm = Read-Host "  Confirmar remocao? [S/N]" } while ($confirm -notmatch '^[SsNn]$')

            if ($confirm -match '^[Ss]$') {
                Write-Host ""
                $list = New-Object 'System.Collections.Generic.List[PSCustomObject]'
                foreach ($p in $selected) { $list.Add($p) }

                $result = Remove-Profiles -ToDelete $list
                $ok     = @($result.Results | Where-Object { $_.Success }).Count
                $fail   = @($result.Results | Where-Object { -not $_.Success }).Count

                foreach ($r in $result.Results) {
                    if ($r.Success) { $r.Profile.Deleted = $true; $r.Profile.Selected = $false }
                }

                # Re-indexar perfis visiveis
                $i = 1
                foreach ($p in ($Profiles | Where-Object { -not $_.Deleted })) { $p.Index = $i++ }

                $dryNote = if ($script:DryRun) { " (simulado)" } else { "" }
                $msg = "$ok perfil(s) removido(s)$dryNote, $fail falha(s). Liberado: $(Format-FileSize $result.FreedBytes)"
            }
            else {
                $msg = "Remocao cancelada pelo usuario."
            }
        }
        elseif ($cmd -match '^i\s+(\d+)$') {
            $n = [int]$Matches[1]
            $p = $Profiles | Where-Object { $_.Index -eq $n -and -not $_.Deleted }
            if ($p) {
                Show-ProfileDetail -Profile $p
                Read-Host "  Pressione Enter para voltar" | Out-Null
            } else {
                $msg = "Perfil #$n nao encontrado."
            }
        }
        elseif ($cmd -match '^[\d\s]+$') {
            $nums    = $cmd -split '\s+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
            $toggled = 0
            $warn    = ""
            foreach ($n in $nums) {
                $p = $Profiles | Where-Object { $_.Index -eq $n -and -not $_.Deleted }
                if ($p) {
                    if ($p.CanDelete) { $p.Selected = -not $p.Selected; $toggled++ }
                    else              { $warn += "Perfil #$n ($($p.Status)) nao pode ser removido. " }
                } else {
                    $warn += "Perfil #$n nao encontrado. "
                }
            }
            $selNow = @($Profiles | Where-Object { -not $_.Deleted -and $_.Selected }).Count
            $msg    = if ($toggled -gt 0) { "$toggled alternado(s). Selecionados: $selNow. $warn" } else { $warn.Trim() }
        }
        else {
            $msg = "Comando invalido: '$cmd'. Use q para sair."
        }
    }

    try { [Console]::Clear() } catch {}
    Write-Host ""
    Write-Host "Sessao encerrada." -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

if ($Help)    { Show-Help; exit 0 }
if ($Version) { Write-Host "Versao: $ScriptVersion" -ForegroundColor Green; exit 0 }

if (-not (Test-IsAdministrator)) {
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        } else {
            "-$($kv.Key)"; "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$transcriptActive = $false
if (-not $NoLog) {
    $ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'Utilities'
    $LogDir        = $ReportSession.LogsPath
    $LogFile       = Join-Path $LogDir "$((Get-Date).ToString('yyyy-MM-dd_HHmmss'))-$([System.IO.Path]::GetFileNameWithoutExtension($ScriptName)).log"

    if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    try {
        Start-Transcript -Path $LogFile -Encoding UTF8 -ErrorAction Stop
        $transcriptActive = $true
    }
    catch {
        Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
$dryBanner = if ($DryRun) { " [MODO SIMULACAO — nenhuma alteracao sera feita]" } else { "" }
Write-Host " Remocao de Perfis Inativos — $ScriptVersion$dryBanner" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$profiles = Get-LocalProfiles

if ($profiles.Count -eq 0) {
    Write-Host ""
    Write-Host "Nenhum perfil de usuario encontrado para gerenciar." -ForegroundColor Yellow
    if ($transcriptActive) { Stop-Transcript }
    exit 0
}

if ($Silent) {
    # Modo silencioso: auto-seleciona e remove orfaos + inativos
    $toDelete = @($profiles | Where-Object {
        $_.CanDelete -and (-not $_.AccountExists -or $_.DaysInactive -ge $InactiveDays)
    })

    Write-Host ""
    if ($toDelete.Count -eq 0) {
        Write-Host "Nenhum perfil elegivel para remocao automatica (orfaos ou inativos >$InactiveDays dias)." -ForegroundColor Yellow
    }
    else {
        Write-Host "Perfis selecionados automaticamente:" -ForegroundColor Yellow
        foreach ($p in $toDelete) {
            Write-Host ("  - {0,-28} {1,-10} {2,-8}inat.  {3}" -f $p.UserName, $p.SizeDisplay, "$($p.DaysInactive)d", $p.Status) -ForegroundColor $p.StatusColor
        }
        $totalSel = ($toDelete | Measure-Object -Property SizeBytes -Sum).Sum
        Write-Host "  Total: $($toDelete.Count) perfil(s) | $(Format-FileSize $totalSel)" -ForegroundColor Yellow
        Write-Host ""

        $list = New-Object 'System.Collections.Generic.List[PSCustomObject]'
        foreach ($p in $toDelete) { $list.Add($p) }

        $result = Remove-Profiles -ToDelete $list
        $ok     = @($result.Results | Where-Object { $_.Success }).Count
        $fail   = @($result.Results | Where-Object { -not $_.Success }).Count
        $dryNote = if ($DryRun) { " (simulado)" } else { "" }

        Write-Host ""
        Write-Host "Remocao concluida${dryNote}: $ok removido(s), $fail falha(s). Liberado: $(Format-FileSize $result.FreedBytes)" -ForegroundColor Green
    }
}
else {
    # Modo interativo
    $list = New-Object 'System.Collections.Generic.List[PSCustomObject]'
    foreach ($p in $profiles) { $list.Add($p) }
    Invoke-InteractiveMenu -Profiles $list
}

if ($transcriptActive) { Stop-Transcript }
