<#
.SYNOPSIS
    Configura acesso remoto (RDP) no Windows.

.DESCRIPTION
    Habilita, desabilita e configura o Area de Trabalho Remota (RDP) no Windows 10/11 Pro+.
    Suporta: diagnostico completo, habilitacao/desabilitacao, mudanca de porta,
    autenticacao NLA, gerenciamento de usuarios e regras de firewall.

    Verificacao de suporte: Windows Home nao suporta hospedagem RDP.
    O script detecta e exibe mensagem orientando para Pro/Enterprise/Education.

    Modo Diagnostico (padrao): Exibe estado atual do RDP.

.PARAMETER Acao
    Acao a executar: Diagnostico (padrao), Habilitar, Desabilitar, ConfigurarPorta,
    AdicionarUsuario, RemoverUsuario, AbrirFirewall, FecharFirewall.

.PARAMETER Porta
    Porta TCP do RDP. Padrao: 3389.

.PARAMETER NivelAutenticacao
    Nivel de autenticacao NLA: Required (padrao, recomendado) ou None.

.PARAMETER Usuario
    Nome do usuario para adicionar/remover do grupo Remote Desktop Users.

.PARAMETER DryRun
    Simula a acao sem executar.

.PARAMETER GerarHtml
    Gera relatorio HTML adicional.

.PARAMETER AbrirRelatorio
    Abre o relatorio ao final.

.PARAMETER Path
    Diretorio raiz de relatorios.

.EXAMPLE
    .\configurar-acesso-remoto.ps1

.EXAMPLE
    .\configurar-acesso-remoto.ps1 -Acao Habilitar

.EXAMPLE
    .\configurar-acesso-remoto.ps1 -Acao ConfigurarPorta -Porta 3390

.EXAMPLE
    .\configurar-acesso-remoto.ps1 -Acao AdicionarUsuario -Usuario "joao"

.EXAMPLE
    .\configurar-acesso-remoto.ps1 -Acao AbrirFirewall -Porta 3390

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Requer Windows Pro, Enterprise ou Education (Home nao suporta hospedagem RDP).
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Habilitar', 'Desabilitar', 'ConfigurarPorta',
                 'AdicionarUsuario', 'RemoverUsuario', 'AbrirFirewall', 'FecharFirewall')]
    [string]$Acao = 'Diagnostico',

    [ValidateRange(1, 65535)]
    [int]$Porta = 3389,

    [ValidateSet('Required', 'None')]
    [string]$NivelAutenticacao = 'Required',

    [string]$Usuario,

    [switch]$DryRun,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Alias('DiretorioSaida')]
    [string]$Path,

    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
try { chcp 65001 | Out-Null } catch { }

$ScriptName = $MyInvocation.MyCommand.Name
$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = Split-Path -Parent $ScriptDir

Import-Module (Join-Path $ToolkitRoot 'modules\WbaToolkit.Core\WbaToolkit.Core.psd1') -Force

if (-not (Test-IsAdministrator)) {
    Write-Warn 'Operacao requer privilegios de Administrador. Reabrindo elevado...'
    $relaunch = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunch) -Verb RunAs
    exit
}

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'acesso-remoto'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Funcoes internas
# ---------------------------------------------------------------------------

function Test-RdpSupport {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { return $true }
    $caption = $os.Caption
    if ($caption -match 'Home') {
        return $false
    }
    return $true
}

function Get-RdpStatus {
    $tsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $tcpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

    $denyConnections = (Get-ItemProperty -Path $tsKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
    $rdpEnabled = ($denyConnections -ne 1)

    $portNumber = (Get-ItemProperty -Path $tcpKey -Name 'PortNumber' -ErrorAction SilentlyContinue).PortNumber
    if (-not $portNumber) { $portNumber = 3389 }

    $nla = (Get-ItemProperty -Path $tcpKey -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
    $nlaEnabled = ($nla -eq 1)

    $svc = Get-Service -Name TermService -ErrorAction SilentlyContinue
    $svcStatus = if ($svc) { $svc.Status.ToString() } else { 'Nao encontrado' }
    $svcStartType = if ($svc) { $svc.StartType.ToString() } else { 'N/A' }

    $rdpUsers = @()
    try {
        $group = [ADSI]"WinNT://./Remote Desktop Users,group"
        $members = @($group.Invoke('Members'))
        $rdpUsers = $members | ForEach-Object {
            $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
        }
    } catch { }

    $fwRule = Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
        Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' } |
        Select-Object -First 1

    $fwCustomPort = Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' -and $_.DisplayName -match "RDP.*$portNumber" } |
        Select-Object -First 1

    [pscustomobject]@{
        RdpEnabled       = $rdpEnabled
        Porta            = $portNumber
        NlaEnabled       = $nlaEnabled
        ServicoStatus    = $svcStatus
        ServicoStartType = $svcStartType
        UsuariosRDP      = @($rdpUsers)
        FirewallRDP      = [bool]$fwRule
        FirewallPorta    = [bool]$fwCustomPort
        SuportaRDP       = (Test-RdpSupport)
    }
}

function Set-RdpEnabled {
    param([bool]$Enabled)
    $tsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $value = if ($Enabled) { 0 } else { 1 }
    Set-ItemProperty -Path $tsKey -Name 'fDenyTSConnections' -Value $value -Type DWord -Force
}

function Set-RdpPortInternal {
    param([int]$NewPort)
    $tcpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    Set-ItemProperty -Path $tcpKey -Name 'PortNumber' -Value $NewPort -Type DWord -Force
}

function Set-RdpNlaInternal {
    param([bool]$Required)
    $tcpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    $value = if ($Required) { 1 } else { 0 }
    Set-ItemProperty -Path $tcpKey -Name 'UserAuthentication' -Value $value -Type DWord -Force
}

function Set-RdpServiceState {
    param([string]$State)
    $svc = Get-Service -Name TermService -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    switch ($State) {
        'Running'  { Start-Service -Name TermService -Force -ErrorAction Stop }
        'Stopped'  { Stop-Service -Name TermService -Force -ErrorAction Stop }
        'Automatic' { Set-Service -Name TermService -StartupType Automatic -ErrorAction Stop }
        'Disabled'  { Set-Service -Name TermService -StartupType Disabled -ErrorAction Stop }
    }
}

function Add-RdpFirewallRule {
    param([int]$RulePort)
    $existing = Get-NetFirewallRule -DisplayName "WBA RDP Custom ($RulePort)" -ErrorAction SilentlyContinue
    if ($existing) {
        Enable-NetFirewallRule -DisplayName "WBA RDP Custom ($RulePort)" -ErrorAction SilentlyContinue
        return
    }
    New-NetFirewallRule -DisplayName "WBA RDP Custom ($RulePort)" `
        -Direction Inbound -Protocol TCP -LocalPort $RulePort `
        -Action Allow -Profile Any -Description "Regra WBA Toolkit para RDP na porta $RulePort" | Out-Null
}

function Remove-RdpFirewallRule {
    param([int]$RulePort)
    $existing = Get-NetFirewallRule -DisplayName "WBA RDP Custom ($RulePort)" -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName "WBA RDP Custom ($RulePort)" -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

try {
    Write-Title "Configuracao de Acesso Remoto (RDP)"

    if (-not (Test-RdpSupport)) {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $caption = if ($os) { $os.Caption } else { 'desconhecida' }
        Write-Host ""
        Write-Host "  [ERRO] Esta versao do Windows ($caption) nao suporta" -ForegroundColor Red
        Write-Host "          hospedagem de Area de Trabalho Remota (RDP)." -ForegroundColor Red
        Write-Host ""
        Write-Host "  RDP requer Windows Pro, Enterprise ou Education." -ForegroundColor Yellow
        Write-Host "  Windows Home so permite CONEXAO remota, nao hospedagem." -ForegroundColor Yellow
        Write-Host ""
        Write-Fail "Operacao encerrada. Versao incompativel: $caption"
        return
    }

    Write-Host ""

    if ($DryRun) {
        Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
        Write-Host ""
    }

    $status = Get-RdpStatus

    switch ($Acao) {
        'Diagnostico' {
            Write-Section "Status do RDP"
            $rdpColor = if ($status.RdpEnabled) { 'Green' } else { 'Red' }
            $rdpIcon  = if ($status.RdpEnabled) { '[ATIVO]' } else { '[INATIVO]' }
            Write-Host "  $rdpIcon RDP" -ForegroundColor $rdpColor

            Write-Host "  Porta:           $($status.Porta)" -ForegroundColor Gray

            $nlaColor = if ($status.NlaEnabled) { 'Green' } else { 'Yellow' }
            $nlaText  = if ($status.NlaEnabled) { 'Ativada (Required)' } else { 'Desativada (None)' }
            Write-Host "  NLA:             $nlaText" -ForegroundColor $nlaColor

            $svcColor = switch ($status.ServicoStatus) {
                'Running' { 'Green' }
                'Stopped' { 'Yellow' }
                default   { 'Red' }
            }
            Write-Host "  Servico:         $($status.ServicoStatus) ($($status.ServicoStartType))" -ForegroundColor $svcColor

            $fwColor = if ($status.FirewallRDP) { 'Green' } else { 'Red' }
            $fwText  = if ($status.FirewallRDP) { 'Ativo' } else { 'Sem regra' }
            Write-Host "  Firewall:        $fwText" -ForegroundColor $fwColor

            Write-Host ""
            Write-Section "Usuarios habilitados"
            if ($status.UsuariosRDP.Count -gt 0) {
                foreach ($u in $status.UsuariosRDP) {
                    Write-Host "  - $u" -ForegroundColor Cyan
                }
            } else {
                Write-Info "Nenhum usuario no grupo Remote Desktop Users."
            }

            Write-Host ""
            if ($status.RdpEnabled -and $status.ServicoStatus -eq 'Running') {
                Write-Ok "RDP operacional na porta $($status.Porta)."
            }
            elseif ($status.RdpEnabled) {
                Write-Warn "RDP habilitado mas servico $($status.ServicoStatus)."
            }
            else {
                Write-Info "RDP desabilitado. Use -Acao Habilitar para ativar."
            }
        }

        'Habilitar' {
            Write-Section "Habilitando RDP"
            if ($DryRun) {
                Write-Info "[DRYRUN] RDP seria habilitado na porta $($status.Porta)."
                Write-Info "[DRYRUN] Servico TermService seria iniciado."
            } else {
                Set-RdpEnabled -Enabled $true
                Write-Ok "RDP habilitado no registro."

                Set-RdpServiceState -State 'Automatic'
                Set-RdpServiceState -State 'Running'
                Write-Ok "Servico TermService em automatico e iniciado."

                if ($NivelAutenticacao -eq 'Required') {
                    Set-RdpNlaInternal -Required $true
                    Write-Ok "NLA (autenticacao de rede) ativada."
                }

                Write-Ok "RDP habilitado e operacional."
            }
        }

        'Desabilitar' {
            Write-Section "Desabilitando RDP"
            if ($DryRun) {
                Write-Info "[DRYRUN] RDP seria desabilitado."
            } else {
                Set-RdpEnabled -Enabled $false
                Write-Ok "RDP desabilitado no registro."
                Write-Warn "Servico TermService mantido. Para parar: -Acao ConfigurarServico"
            }
        }

        'ConfigurarPorta' {
            Write-Section "Configurando porta RDP"
            if ($DryRun) {
                Write-Info "[DRYRUN] Porta seria alterada: $($status.Porta) -> $Porta"
            } else {
                Set-RdpPortInternal -NewPort $Porta
                Write-Ok "Porta alterada para $Porta."

                Add-RdpFirewallRule -RulePort $Porta
                Write-Ok "Regra de firewall criada para porta $Porta."

                Write-Warn "Reinicie o servico TermService ou o sistema para aplicar a nova porta."
            }
        }

        'AdicionarUsuario' {
            if (-not $Usuario) {
                Write-Fail "Parametro -Usuario obrigatorio para acao AdicionarUsuario."
                return
            }
            Write-Section "Adicionando usuario ao grupo Remote Desktop Users"
            if ($DryRun) {
                Write-Info "[DRYRUN] Usuario '$Usuario' seria adicionado ao grupo."
            } else {
                try {
                    $group = [ADSI]"WinNT://./Remote Desktop Users,group"
                    $user  = [ADSI]"WinNT://./$Usuario,user"
                    $group.Invoke('Add', $user.Path)
                    Write-Ok "Usuario '$Usuario' adicionado ao grupo Remote Desktop Users."
                } catch {
                    Write-Fail "Falha ao adicionar usuario: $($_.Exception.Message)"
                }
            }
        }

        'RemoverUsuario' {
            if (-not $Usuario) {
                Write-Fail "Parametro -Usuario obrigatorio para acao RemoverUsuario."
                return
            }
            Write-Section "Removendo usuario do grupo Remote Desktop Users"
            if ($DryRun) {
                Write-Info "[DRYRUN] Usuario '$Usuario' seria removido do grupo."
            } else {
                try {
                    $group = [ADSI]"WinNT://./Remote Desktop Users,group"
                    $user  = [ADSI]"WinNT://./$Usuario,user"
                    $group.Invoke('Remove', $user.Path)
                    Write-Ok "Usuario '$Usuario' removido do grupo Remote Desktop Users."
                } catch {
                    Write-Fail "Falha ao remover usuario: $($_.Exception.Message)"
                }
            }
        }

        'AbrirFirewall' {
            Write-Section "Abrindo porta $Porta no firewall"
            if ($DryRun) {
                Write-Info "[DRYRUN] Regra de firewall seria criada para porta $Porta."
            } else {
                Add-RdpFirewallRule -RulePort $Porta
                Write-Ok "Regra de firewall criada: WBA RDP Custom ($Porta)"
            }
        }

        'FecharFirewall' {
            Write-Section "Fechando porta $Porta no firewall"
            if ($DryRun) {
                Write-Info "[DRYRUN] Regra de firewall seria removida para porta $Porta."
            } else {
                Remove-RdpFirewallRule -RulePort $Porta
                Write-Ok "Regra de firewall removida: WBA RDP Custom ($Porta)"
            }
        }
    }

    Write-Host ""

    $jsonReport = Join-Path $ReportSession.Path 'acesso-remoto-status.json'
    $status | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReport -Encoding UTF8
    Write-Ok "Relatorio: $jsonReport"

    if ($GerarHtml) {
        $htmlPath = Join-Path $ReportSession.Path 'acesso-remoto.html'
        $rdpStatus = if ($status.RdpEnabled) { 'ATIVO' } else { 'INATIVO' }
        $rdpColor  = if ($status.RdpEnabled) { '#d4edda' } else { '#f8d7da' }
        $nlaStatus = if ($status.NlaEnabled) { 'Ativada' } else { 'Desativada' }
        $bodyHtml = @"
<h2>Status do RDP</h2>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse">
<tr><th>RDP</th><th>Porta</th><th>NLA</th><th>Servico</th><th>Firewall</th></tr>
<tr style='background-color:$rdpColor'><td>$rdpStatus</td><td>$($status.Porta)</td><td>$nlaStatus</td><td>$($status.ServicoStatus)</td><td>$(if ($status.FirewallRDP) { 'Ativo' } else { 'Sem regra' })</td></tr>
</table>

<h2>Usuarios RDP ($($status.UsuariosRDP.Count))</h2>
<ul>
$($status.UsuariosRDP | ForEach-Object { "<li>$_</li>" } | Out-String)
</ul>
"@
        $html = New-ToolkitHtmlReport -Title "Acesso Remoto (RDP)" `
            -Subtitle "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            -Icon "&#128421;" -Body $bodyHtml -FooterText "Gerado por WBA Windows Toolkit"
        [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($true))
        Write-Ok "HTML: $htmlPath"

        if ($AbrirRelatorio) { Start-Process $htmlPath }
    }

    Write-Host ""
    Write-Ok "Configuracao de acesso remoto concluida."

} catch {
    Write-Fail "Erro: $($_.Exception.Message)"
} finally {
    if ($transcriptActive) { Stop-Transcript }
}
