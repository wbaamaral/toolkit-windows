#requires -version 5.1
<#
.SYNOPSIS
    Gerencia o logon automatico (autologon) do Windows: diagnostico, habilitar,
    desabilitar e editar.

.DESCRIPTION
    Interface operacional para o modulo WbaToolkit.Identity. A senha do autologon e
    sempre armazenada como segredo LSA ('DefaultPassword'), nunca em texto claro no
    registro (conformidade ADR 0005). Faz backup dos valores atuais antes de alterar.

    No modo Diagnostico (padrao), apenas le e exibe o estado atual e gera relatorio.
    No modo Assistido, abre o gerenciador interativo (habilitar/desabilitar/editar).
    O parametro -Acao permite uso nao-interativo para automacao.

    A senha NUNCA e aceita por parametro de texto: e sempre solicitada de forma segura
    (Read-Host -AsSecureString) e nunca aparece em logs ou relatorios.

.PARAMETER Modo
    Diagnostico : le e exibe o estado do autologon; sem alteracoes (padrao).
    Assistido   : abre o gerenciador interativo.

.PARAMETER Acao
    Uso nao-interativo: Habilitar, Desabilitar ou Editar. Requer -UserName quando aplicavel.

.PARAMETER UserName
    Conta alvo (para -Acao Habilitar/Editar).

.PARAMETER Domain
    Dominio da conta. Padrao: nome da maquina (conta local).

.PARAMETER AutoLogonCount
    Numero de logons automaticos antes de o Windows desativar o autologon.

.PARAMETER DryRun
    Simula operacoes que alterariam o sistema, sem executa-las.

.PARAMETER Path
    Raiz de relatorios. Quando omitido, usa a configuracao persistente do toolkit
    ou C:\WBA\Relatorios.

.EXAMPLE
    .\gerenciar-login-automatico.ps1

    Mostra o estado atual do autologon (somente leitura).

.EXAMPLE
    .\gerenciar-login-automatico.ps1 -Modo Assistido

    Abre o gerenciador interativo.

.EXAMPLE
    .\gerenciar-login-automatico.ps1 -Acao Habilitar -UserName kiosk -AutoLogonCount 1

    Habilita o autologon para a conta local 'kiosk' (a senha sera solicitada).

.EXAMPLE
    .\gerenciar-login-automatico.ps1 -Acao Desabilitar

    Desabilita o autologon e limpa a senha do segredo LSA.

.NOTAS
    Requer execucao como Administrador.
    Autologon reduz a seguranca fisica da estacao; use com criterio.
    Modulos WbaToolkit.Core e WbaToolkit.Identity sao carregados automaticamente.
#>
param(
    [ValidateSet('Diagnostico', 'Assistido')]
    [string]$Modo = 'Diagnostico',

    [ValidateSet('Habilitar', 'Desabilitar', 'Editar')]
    [string]$Acao,

    [string]$UserName,

    [string]$Domain = $env:COMPUTERNAME,

    [int]$AutoLogonCount,

    [switch]$DryRun,

    [Alias('DiretorioSaida')]
    [string]$Path
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
try { chcp 65001 | Out-Null } catch { }

$ScriptName = if ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } else { Split-Path -Leaf $PSCommandPath }
$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

$ScriptVersion = 'v1.0'
$ToolkitRoot   = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1')     -Force -ErrorAction Stop
Import-Module (Join-Path $ToolkitRoot 'modules/WbaToolkit.Identity/WbaToolkit.Identity.psd1') -Force -ErrorAction Stop

# WBA-DOCS: Category=Identidade; Manual=Gerenciamento de login automatico do Windows

$ErrorActionPreference = 'Continue'

# --- elevacao -----------------------------------------------------------------
if (-not (Test-IsAdministrator)) {
    Write-Warn 'Operacao requer privilegios de Administrador. Reabrindo elevado...'
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        }
        else {
            "-$($kv.Key)"; "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

# --- sessao -------------------------------------------------------------------
$session = Initialize-ScriptSession -ModuleName 'WbaToolkit.Identity' -BasePath $Path -ExecutionMode $Modo
$logFile = Join-Path $session.LogsPath 'gerenciar-login-automatico.log'

function Write-AutologonLog {
    param([string]$Level = 'INFO', [Parameter(Mandatory = $true)][string]$Message)
    Write-ScriptLog -Message $Message -Level $Level -LogPath $logFile
}

Write-Title "WBA Windows Toolkit - Login Automatico $ScriptVersion"
Write-Info "Relatorios em: $($session.Path)"
Write-AutologonLog -Message "Sessao iniciada. Modo: $Modo. Acao: $Acao. DryRun: $DryRun."

# --- acao nao-interativa ------------------------------------------------------
$sessionLog = @()

if ($Acao) {
    switch ($Acao) {
        'Habilitar' {
            if ([string]::IsNullOrWhiteSpace($UserName)) {
                Write-Fail '-UserName e obrigatorio para -Acao Habilitar.'
                exit 1
            }
            $pwd = Read-Host 'Senha da conta' -AsSecureString
            $params = @{ UserName = $UserName; Domain = $Domain; Password = $pwd; DryRun = $DryRun }
            if ($PSBoundParameters.ContainsKey('AutoLogonCount')) { $params['AutoLogonCount'] = $AutoLogonCount }
            $sessionLog = @(Enable-Autologon @params)
        }
        'Desabilitar' {
            $sessionLog = @(Disable-Autologon -DryRun:$DryRun)
        }
        'Editar' {
            $params = @{ DryRun = $DryRun }
            if ($PSBoundParameters.ContainsKey('UserName'))       { $params['UserName'] = $UserName }
            if ($PSBoundParameters.ContainsKey('Domain'))         { $params['Domain'] = $Domain }
            if ($PSBoundParameters.ContainsKey('AutoLogonCount')) { $params['AutoLogonCount'] = $AutoLogonCount }
            if (Read-YesNo -Question 'Alterar a senha?' -DefaultYes $false) {
                $params['Password'] = Read-Host 'Nova senha' -AsSecureString
            }
            $sessionLog = @(Set-Autologon @params)
        }
    }
    foreach ($r in $sessionLog) {
        $lvl = if ($r.Success) { 'INFO' } else { 'WARN' }
        Write-AutologonLog -Level $lvl -Message "$($r.Action) '$($r.Name)': $($r.Message)"
    }
}
elseif ($Modo -eq 'Assistido') {
    $sessionLog = @(Invoke-AutologonManager -DryRun:$DryRun)
    foreach ($r in $sessionLog) {
        $lvl = if ($r.Success) { 'INFO' } else { 'WARN' }
        Write-AutologonLog -Level $lvl -Message "$($r.Action) '$($r.Name)': $($r.Message)"
    }
}

# --- diagnostico / relatorio final --------------------------------------------
Write-Section 'Estado atual do autologon'
$status = Get-AutologonStatus

Write-Info ("Habilitado          : {0}" -f $(if ($status.Enabled) { 'Sim' } else { 'Nao' }))
Write-Info ("Usuario             : {0}" -f $status.UserName)
Write-Info ("Dominio             : {0}" -f $status.Domain)
Write-Info ("AutoLogonCount      : {0}" -f $status.AutoLogonCount)
Write-Info ("Senha protegida LSA : {0}" -f $(if ($status.PasswordInLsa) { 'Sim' } else { 'Nao' }))
if ($status.PlaintextPasswordInRegistry) {
    Write-Warn 'ATENCAO: existe senha em TEXTO CLARO no registro (DefaultPassword). Considere desabilitar e reabilitar para migrar para a LSA.'
}

$report = [pscustomobject]@{
    Computador     = $env:COMPUTERNAME
    Data           = (Get-Date).ToString('o')
    VersaoScript   = $ScriptVersion
    Modo           = $Modo
    Acao           = $Acao
    DryRun         = [bool]$DryRun
    Estado         = $status
    Operacoes      = @($sessionLog)
}

$jsonPath = Join-Path $session.Path 'relatorio-login-automatico.json'
Write-TextFileUtf8 -Path $jsonPath -Content ($report | ConvertTo-Json -Depth 6)

Write-AutologonLog -Message 'Sessao encerrada.'
Write-Ok "Relatorio JSON: $jsonPath"
Write-Ok "Logs: $($session.LogsPath)"
Write-Title "Sessao concluida: $($session.Path)"
