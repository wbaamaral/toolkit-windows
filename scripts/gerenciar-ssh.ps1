<#
.SYNOPSIS
    Gerenciamento do OpenSSH Server, chaves e configuracao SSH no Windows.

.DESCRIPTION
    Instala, configura e gerencia o OpenSSH Server built-in do Windows.
    Suporta: diagnostico completo, instalacao, servico, chaves de host,
    chaves de usuario, authorized_keys e testes de conectividade.

.PARAMETER Acao
    Acao a executar: Diagnostico (padrao), Instalar, Habilitar, Desabilitar,
    Parar, Iniciar, Configurar, GerarChaveHost, GerarChaveUsuario,
    AdicionarChave, RemoverChave, ListarChaves, TestarConexao.

.PARAMETER Port
    Porta TCP do SSH. Padrao: 22.

.PARAMETER UserName
    Nome do usuario para operacoes de chave. Padrao: usuario atual.

.PARAMETER PublicKeyPath
    Caminho da chave publica para adicionar ao authorized_keys.

.PARAMETER KeyType
    Tipo de chave: ed25519 (padrao), rsa, ecdsa.

.PARAMETER ConfigKey
    Diretiva do sshd_config a alterar (ex.: PasswordAuthentication).

.PARAMETER ConfigValue
    Valor da diretiva (ex.: no, yes, 2222).

.PARAMETER DryRun
    Simula a acao sem executar.

.PARAMETER GerarHtml
    Gera relatorio HTML adicional.

.PARAMETER Path
    Diretorio raiz de relatorios.

.PARAMETER Help
    Exibe a ajuda e encerra.

.EXAMPLE
    .\gerenciar-ssh.ps1

.EXAMPLE
    .\gerenciar-ssh.ps1 -Acao Instalar

.EXAMPLE
    .\gerenciar-ssh.ps1 -Acao Configurar -ConfigKey Port -ConfigValue 2222

.EXAMPLE
    .\gerenciar-ssh.ps1 -Acao GerarChaveHost -KeyType ed25519

.EXAMPLE
    .\gerenciar-ssh.ps1 -Acao AdicionarChave -PublicKeyPath 'C:\chaves\id_ed25519.pub' -UserName 'joao'

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Modulos requeridos: WbaToolkit.Core, WbaToolkit.SSH
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Instalar', 'Habilitar', 'Desabilitar', 'Parar', 'Iniciar',
                 'Configurar', 'GerarChaveHost', 'GerarChaveUsuario',
                 'AdicionarChave', 'RemoverChave', 'ListarChaves', 'TestarConexao')]
    [string]$Acao = 'Diagnostico',

    [ValidateRange(1, 65535)]
    [int]$Port = 22,

    [string]$UserName,

    [string]$PublicKeyPath,

    [ValidateSet('ed25519', 'rsa', 'ecdsa')]
    [string]$KeyType = 'ed25519',

    [string]$ConfigKey,

    [string]$ConfigValue,

    [switch]$DryRun,

    [switch]$GerarHtml,

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

$actionRequiresAdmin = @('Instalar', 'Habilitar', 'Desabilitar', 'Parar', 'Iniciar', 'Configurar', 'GerarChaveHost')
if ($Acao -in $actionRequiresAdmin -and -not (Test-IsAdministrator)) {
    Write-Warning "A acao '$Acao' exige privilegios administrativos. Solicitando elevacao..."
    $command = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) -Verb RunAs
    exit 0
}

$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$sshModuleRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.SSH'

foreach ($mod in @($coreModuleRoot, $sshModuleRoot)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot, $sshModuleRoot)) {
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
    exit 1
}

# WBA-DOCS: Category=Networking; Manual=Gerenciamento de OpenSSH Server no Windows

$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'ssh'
$logFile = Join-Path $ReportSession.LogsPath "$($ScriptName -replace '\.ps1$','').log"
$transcriptActive = $false
try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcriptActive = $true
} catch {
    Write-Warning "Nao foi possivel iniciar o log de transcricao: $($_.Exception.Message)"
}

Write-Title "Gerenciamento de OpenSSH Server"

if ($DryRun) {
    Write-Warn "MODO DRYRUN: Nenhuma alteracao sera aplicada."
    Write-Host ""
}

# ── Validações ─────────────────────────────────────────────────────────────

if ($Acao -eq 'Configurar') {
    if ([string]::IsNullOrWhiteSpace($ConfigKey)) {
        Write-Host "[FALHA] Acao Configurar requer -ConfigKey." -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

if ($Acao -eq 'AdicionarChave') {
    if ([string]::IsNullOrWhiteSpace($PublicKeyPath)) {
        Write-Host "[FALHA] Acao AdicionarChave requer -PublicKeyPath." -ForegroundColor Red
        if ($transcriptActive) { Stop-Transcript }
        exit 1
    }
}

# ── Diagnóstico ────────────────────────────────────────────────────────────

if ($Acao -eq 'Diagnostico') {
    Write-Title "Diagnostico SSH"

    $status = Get-SshServerStatus

    Write-Host ""
    $featColor = if ($status.FeatureInstalled) { 'Green' } else { 'Red' }
    Write-Host "  Feature:         " -NoNewline
    Write-Host "$($status.FeatureState)" -ForegroundColor $featColor

    $svcColor = switch ($status.ServiceStatus) {
        'Running' { 'Green' }
        'Stopped' { 'Yellow' }
        default   { 'Red' }
    }
    Write-Host "  Servico:         " -NoNewline
    Write-Host "$($status.ServiceStatus)" -ForegroundColor $svcColor
    Write-Host "  Autostart:       $($status.ServiceStartType)"
    Write-Host "  Porta:           $($status.Port)"

    $fwColor = if ($status.FirewallRuleExists -and $status.FirewallRuleEnabled) { 'Green' }
               elseif ($status.FirewallRuleExists) { 'Yellow' }
               else { 'Red' }
    Write-Host "  Firewall:        " -NoNewline
    $fwText = if ($status.FirewallRuleExists) {
        if ($status.FirewallRuleEnabled) { 'Ativo' } else { 'Desabilitado' }
    } else { 'Sem regra' }
    Write-Host "$fwText" -ForegroundColor $fwColor

    Write-Host "  Chaves host:     $($status.HostKeysCount)"
    foreach ($hk in $status.HostKeys) {
        Write-Host "    - $($hk.Type): $($hk.Path)" -ForegroundColor DarkGray
    }

    Write-Host "  Admin auth keys: $($status.AdminKeysCount)"

    if ($status.ConfigExists) {
        $config = Get-SshdConfig
        Write-Host ""
        Write-Host "  Configuracoes relevantes:" -ForegroundColor Cyan
        $relevantKeys = @('Port', 'PasswordAuthentication', 'PubkeyAuthentication',
                          'PermitRootLogin', 'AllowGroups', 'AllowUsers',
                          'DenyGroups', 'DenyUsers', 'Subsystem')
        foreach ($k in $relevantKeys) {
            if ($config.Config.ContainsKey($k)) {
                $val = $config.Config[$k]
                Write-Host "    $k = $val"
            }
        }
    }

    Write-Host ""
    if ($status.FeatureInstalled -and $status.ServiceStatus -eq 'Running') {
        Write-Ok "SSH Server operacional na porta $($status.Port)."
    }
    elseif ($status.FeatureInstalled) {
        Write-Warn "SSH Server instalado mas servico $($status.ServiceStatus)."
    }
    else {
        Write-Host "  [INFO] SSH Server nao instalado. Use -Acao Instalar." -ForegroundColor Yellow
    }
}

# ── Ações ───────────────────────────────────────────────────────────────────

switch ($Acao) {
    'Instalar' {
        Write-Title "Instalando OpenSSH Server"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0" -ForegroundColor Yellow
        }
        else {
            $result = Install-SshServer
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Host "  [FALHA] $($result.Message)" -ForegroundColor Red }
        }
    }

    'Habilitar' {
        Write-Title "Habilitando SSH Server"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Set-Service sshd -StartupType Automatic; Start-Service sshd" -ForegroundColor Yellow
            Write-Host "  DRY-RUN: New-NetFirewallRule 'OpenSSH Server (sshd)' Port $Port" -ForegroundColor Yellow
        }
        else {
            $result = Enable-SshServer -Port $Port
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Host "  [FALHA] $($result.Message)" -ForegroundColor Red }
        }
    }

    'Desabilitar' {
        Write-Title "Desabilitando SSH Server"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Stop-Service sshd; Set-Service sshd -StartupType Manual" -ForegroundColor Yellow
        }
        else {
            $result = Disable-SshServer
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Host "  [FALHA] $($result.Message)" -ForegroundColor Red }
        }
    }

    'Parar' {
        Write-Title "Parando SSH Server"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Stop-Service sshd" -ForegroundColor Yellow
        }
        else {
            try {
                Stop-Service -Name sshd -Force -ErrorAction Stop
                Write-Ok "Servico sshd parado."
            }
            catch { Write-Host "  [FALHA] $($_.Exception.Message)" -ForegroundColor Red }
        }
    }

    'Iniciar' {
        Write-Title "Iniciando SSH Server"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Start-Service sshd" -ForegroundColor Yellow
        }
        else {
            try {
                Start-Service -Name sshd -ErrorAction Stop
                Write-Ok "Servico sshd iniciado."
            }
            catch { Write-Host "  [FALHA] $($_.Exception.Message)" -ForegroundColor Red }
        }
    }

    'Configurar' {
        Write-Title "Configurando sshd_config"
        if ($DryRun) {
            Write-Host "  DRY-RUN: $ConfigKey = $ConfigValue" -ForegroundColor Yellow
        }
        else {
            $settings = @{ $ConfigKey = $ConfigValue }
            $result = Set-SshdConfig -Settings $settings
            if ($result.Success) {
                Write-Ok $result.Message
                if ($result.Applied) {
                    foreach ($a in $result.Applied) { Write-Host "    + $a" -ForegroundColor Green }
                }
                Write-Host "  Backup: $($result.BackupPath)" -ForegroundColor DarkGray
                if ($result.RestartRequired) {
                    Write-Host "  Reinicie o servico sshd para aplicar." -ForegroundColor Yellow
                }
            }
            else { Write-Host "  [FALHA] $($result.Message)" -ForegroundColor Red }
        }
    }

    'GerarChaveHost' {
        Write-Title "Gerando chave de host $KeyType"
        if ($DryRun) {
            Write-Host "  DRY-RUN: ssh-keygen -t $KeyType" -ForegroundColor Yellow
        }
        else {
            $result = New-SshHostKey -KeyType $KeyType
            if ($result.Success) {
                Write-Ok $result.Message
                if ($result.Generated) {
                    Write-Host "  Public: $($result.PublicKeyPath)" -ForegroundColor Cyan
                    Write-Host "  $($result.PublicKey)" -ForegroundColor DarkGray
                }
            }
            else { Write-Host "  [FALHA] $($result.Message)" -ForegroundColor Red }
        }
    }

    'GerarChaveUsuario' {
        $targetUser = if ($UserName) { $UserName } else { $env:USERNAME }
        Write-Title "Gerando chave $KeyType para $targetUser"
        if ($DryRun) {
            Write-Host "  DRY-RUN: ssh-keygen -t $KeyType -f C:\Users\$targetUser\.ssh\id_$KeyType" -ForegroundColor Yellow
        }
        else {
            $result = New-SshUserKey -UserName $targetUser -KeyType $KeyType
            if ($result.Success) {
                Write-Ok $result.Message
                if ($result.Generated) {
                    Write-Host "  Privada: $($result.KeyPath)" -ForegroundColor Cyan
                    Write-Host "  Publica: $($result.PublicKeyPath)" -ForegroundColor Cyan
                    Write-Host "  $($result.PublicKey)" -ForegroundColor DarkGray
                }
            }
            else { Write-Host "  [FALHA] $($result.Message)" -ForegroundColor Red }
        }
    }

    'AdicionarChave' {
        $targetUser = if ($UserName) { $UserName } else { $env:USERNAME }
        Write-Title "Adicionando chave publica para $targetUser"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Add-SshAuthorizedKey -PublicKeyPath $PublicKeyPath -UserName $targetUser" -ForegroundColor Yellow
        }
        else {
            $result = Add-SshAuthorizedKey -PublicKeyPath $PublicKeyPath -UserName $targetUser
            if ($result.Success) { Write-Ok $result.Message }
            else { Write-Host "  [FALHA] $($result.Message)" -ForegroundColor Red }
        }
    }

    'RemoverChave' {
        $targetUser = if ($UserName) { $UserName } else { $env:USERNAME }
        Write-Title "Removendo chave publica de $targetUser"
        if ($DryRun) {
            Write-Host "  DRY-RUN: Remove-SshAuthorizedKey -UserName $targetUser" -ForegroundColor Yellow
        }
        else {
            $keys = Get-SshAuthorizedKey -UserName $targetUser
            if ($keys.Count -eq 0) {
                Write-Host "  Nenhuma chave encontrada no authorized_keys." -ForegroundColor Yellow
            }
            else {
                Write-Host ""
                Write-Host "  Chaves encontradas:" -ForegroundColor Cyan
                foreach ($k in $keys) {
                    Write-Host "    [$($k.Index)] $($k.Type) $($k.Fingerprint) $($k.Comment)"
                }
                Write-Host ""
                $idx = Read-Host "  Indice da chave a remover (ou Enter para cancelar)"
                if ($idx -match '^\d+$') {
                    $removeResult = Remove-SshAuthorizedKey -Index ([int]$idx) -UserName $targetUser
                    if ($removeResult.Success) { Write-Ok $removeResult.Message }
                    else { Write-Host "  [FALHA] $($removeResult.Message)" -ForegroundColor Red }
                }
                else {
                    Write-Host "  Operacao cancelada." -ForegroundColor Yellow
                }
            }
        }
    }

    'ListarChaves' {
        $targetUser = if ($UserName) { $UserName } else { $env:USERNAME }
        Write-Title "Chaves authorized_keys de $targetUser"

        $keys = Get-SshAuthorizedKey -UserName $targetUser
        if ($keys.Count -eq 0) {
            Write-Host "  Nenhuma chave publica encontrada." -ForegroundColor Yellow
        }
        else {
            Write-Host ""
            foreach ($k in $keys) {
                Write-Host "  [$($k.Index)] $($k.Type) $($k.Fingerprint) $($k.Comment)"
            }
            Write-Host ""
            Write-Ok "$($keys.Count) chave(s) encontrada(s)."
        }
    }

    'TestarConexao' {
        Write-Title "Testando conectividade SSH"
        $testResult = Test-SshConnectivity -Host localhost -Port $Port

        Write-Host ""
        $portColor = if ($testResult.PortOpen) { 'Green' } else { 'Red' }
        Write-Host "  Porta ${Port}: " -NoNewline
        Write-Host "$(if ($testResult.PortOpen) { 'ABERTA' } else { 'FECHADA' })" -ForegroundColor $portColor

        if ($testResult.Banner) {
            Write-Host "  Banner: $($testResult.Banner)" -ForegroundColor Cyan
        }

        if ($testResult.PortOpen) {
            Write-Ok "SSH Server respondendo na porta $Port."
        }
        else {
            Write-Host "  [INFO] SSH Server nao respondeu na porta $Port." -ForegroundColor Yellow
        }
    }
}

# ── Relatórios ─────────────────────────────────────────────────────────────

if ($Acao -in @('Diagnostico', 'Configurar')) {
    $status = Get-SshServerStatus
    $jsonPath = Join-Path $ReportSession.Path 'ssh-status.json'

    $report = [pscustomobject]@{
        GeneratedAt  = (Get-Date)
        ComputerName = $env:COMPUTERNAME
        Action       = $Acao
        Status       = $status
    }

    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-Host ""
    Write-Ok "Relatorio: $jsonPath"
}

if ($transcriptActive) { Stop-Transcript }

Write-Host ""
Write-Ok "Gerenciamento SSH concluido."
