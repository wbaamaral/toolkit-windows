# =============================================================================
# [VALIDADO] Execucao real em Windows 10 Pro build 19045 PT-BR (SRVNFE01).
# Validado em 2026-06-22: 6/6 tweaks OK, GPO+AutoLogon+secedit limpos,
# Sysprep generalizou com novo SID, OOBE sem restricao de senha. BCK-022.
# =============================================================================
#requires -version 5.1
<#
.SYNOPSIS
    Preparacao do sistema Windows para criacao de imagem corporativa.

.DESCRIPTION
    Aplica um conjunto curado de tweaks ao perfil Default do Windows, garantindo
    que toda nova conta de usuario criada a partir da imagem herde as configuracoes
    padrao da organizacao.

    O operador e sempre apresentado a uma simulacao completa antes de qualquer
    alteracao no sistema. A execucao real exige confirmacao explicita digitando
    CONFIRMAR. Um backup do perfil Default e criado automaticamente antes das
    modificacoes.

    Compativel com Windows 10 Pro (build 10240+) e Windows 11.

.PARAMETER ApenasDryRun
    Exibe a simulacao completa e encerra sem efetuar alteracoes.
    Util para verificar quais tweaks serao aplicados antes de executar.

.PARAMETER SemSysprep
    Aplica os tweaks ao perfil Default, mas nao oferece executar o sysprep.exe.
    Use quando o sysprep sera iniciado por outra ferramenta ou em etapa posterior.

.PARAMETER Path
    Raiz de relatorios da sessao. Quando omitido, usa a configuracao persistente
    do toolkit ou C:\WBA\Relatorios.

.USO
    Simular sem alterar o sistema:
        .\Preparar-Imagem-Windows.ps1 -ApenasDryRun

    Aplicar tweaks sem executar sysprep.exe:
        .\Preparar-Imagem-Windows.ps1 -SemSysprep

    Fluxo completo (tweaks + oferta de sysprep.exe):
        .\Preparar-Imagem-Windows.ps1

.NOTAS
    Requer execucao como Administrador.
    O backup do perfil Default e gravado em BackupsPath da sessao de relatorios.
#>
param(
    [switch]$ApenasDryRun,
    [switch]$SemSysprep,
    [switch]$Confirmar,
    [switch]$ConfirmarSysprep,
    [Alias('DiretorioSaida')]
    [string]$Path,
    [string[]]$IgnorarBloqueadoresAppx = @()
)

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

$ScriptVersion       = 'v1.0'
$ToolkitRoot         = Split-Path -Parent $PSScriptRoot
$coreModulePath      = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$maintenancePath     = Join-Path $ToolkitRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1'
$regfilesSysprepDir  = Join-Path $ToolkitRoot 'regfiles/sysprep'

Import-Module $coreModulePath  -Force -ErrorAction Stop
Import-Module $maintenancePath -Force -ErrorAction Stop

# WBA-DOCS: Category=Maintenance; Manual=Preparacao de Imagem Windows

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$script:Session = $null

# ─── helpers locais ──────────────────────────────────────────────────────────

function Write-SysprepLog {
    [CmdletBinding()]
    param(
        [string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )
    $logPath = if ($script:Session) { Join-Path $script:Session.LogsPath 'preparar-imagem.log' } else { $null }
    Write-ScriptLog -Message $Message -Level $Level -LogPath $logPath
}

function Save-SysprepPreparationReport {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)]$Ambiente,
        [Parameter(Mandatory = $true)]$Resultados,
        [Parameter(Mandatory = $true)][string]$SysprepEstado,
        [bool]$SysprepExecutado    = $false,
        [bool]$SysprepBloqueado    = $false,
        $SysprepExitCode           = $null,
        [object[]]$SysprepBloqueadores = @(),
        [string]$MachineSid        = ''
    )
    $aplicados = @($Resultados | Where-Object { $_.Success })
    $falhos    = @($Resultados | Where-Object { -not $_.Success })

    $relatorio = [pscustomobject]@{
        Inicio                 = $Session.StartedAt
        Fim                    = Get-Date
        Modo                   = $Session.Mode
        ApenasDryRun           = [bool]$ApenasDryRun
        SemSysprep             = [bool]$SemSysprep
        ComputerName           = $env:COMPUTERNAME
        MachineSidAntesSysprep = $MachineSid
        OsVersion              = $Ambiente.OsVersion
        BuildNumber            = $Ambiente.BuildNumber
        TweaksAplicados        = $aplicados.Count
        TweaksFalhos           = $falhos.Count
        Tweaks                 = @($Resultados)
        SysprepEstado             = $SysprepEstado
        SysprepExecutado          = $SysprepExecutado
        SysprepBloqueado          = $SysprepBloqueado
        SysprepExitCode           = $SysprepExitCode
        SysprepBloqueadores       = @($SysprepBloqueadores)
        IgnorarBloqueadoresAppx   = @($IgnorarBloqueadoresAppx)
    }

    $jsonPath = Join-Path $Session.Path 'relatorio-preparacao-imagem.json'
    $relatorio | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath
    return $jsonPath
}

# ─── inicializacao ───────────────────────────────────────────────────────────

Write-Title "WBA Windows Toolkit - Preparacao de Imagem Windows $ScriptVersion"

if ($ApenasDryRun) {
    Write-Warn 'MODO APENAS DRY-RUN: nenhuma alteracao sera feita no sistema.'
}

$script:Session = Initialize-ScriptSession `
    -ModuleName 'WbaToolkit.Maintenance' `
    -BasePath $Path `
    -ExecutionMode 'Preparacao'

Write-SysprepLog -Message "Sessao iniciada. ApenasDryRun: $ApenasDryRun. SemSysprep: $SemSysprep. IgnorarBloqueadoresAppx: $($IgnorarBloqueadoresAppx -join ', ')."
Write-Info "Relatorios em: $($script:Session.Path)"

# ─── sid da maquina ───────────────────────────────────────────────────────────

$machineSid = ''
try {
    $localUser = Get-LocalUser -ErrorAction Stop | Select-Object -First 1
    if ($localUser -and $localUser.SID) {
        $userSid  = $localUser.SID.Value
        $lastDash = $userSid.LastIndexOf('-')
        if ($lastDash -gt 0) {
            $machineSid = $userSid.Substring(0, $lastDash)
        }
    }
}
catch {
    Write-SysprepLog -Level 'WARN' -Message "Nao foi possivel capturar SID da maquina: $($_.Exception.Message)"
}

if ($machineSid) {
    Write-Info "SID da maquina (pre-Sysprep): $machineSid"
    Write-SysprepLog -Message "SID da maquina antes do Sysprep: $machineSid"
}

# ─── pre-verificacao ──────────────────────────────────────────────────────────

Write-Section 'Verificacao de pre-requisitos'

$ambiente = Test-SysprepEnvironment -AppxPolicy 'Warn'

foreach ($aviso in $ambiente.Warnings) {
    Write-SysprepLog -Level 'WARN' -Message $aviso
}

$autoLogonEncontrado = $ambiente.AutoLogonDetectado
$gpoEncontrado       = $ambiente.GpoDetectado

if ($autoLogonEncontrado) {
    Write-Warn 'AutoLogon detectado (AutoAdminLogon=1). Sera desativado antes da execucao do Sysprep.'
}
if ($gpoEncontrado) {
    Write-Warn 'Diretivas de grupo encontradas no registro. Serao removidas antes do Sysprep.'
}

if ($ambiente.SysprepBlockers -and $ambiente.SysprepBlockers.Count -gt 0) {
    Write-Warn 'Foram encontrados pacotes Appx que podem bloquear o sysprep.exe.'
    Write-Warn 'A preparacao do perfil Default pode continuar, mas a generalizacao sera bloqueada ate a correcao.'
    Write-SysprepLog -Level 'WARN' -Message "Appx em modo aviso: $($ambiente.SysprepBlockers.Count) possivel(is) bloqueador(es)."
}

if (-not $ambiente.IsValid) {
    foreach ($erro in $ambiente.Errors) {
        Write-SysprepLog -Level 'ERROR' -Message $erro
    }

    $estadoFalha = if ($ambiente.SysprepBlockers -and $ambiente.SysprepBlockers.Count -gt 0) {
        Write-Fail 'Sysprep bloqueado: existem pacotes Appx instalados para usuario, mas nao provisionados para todos os usuarios.'
        Write-Fail 'Consulte o log e valide manualmente antes de tentar generalizar a imagem.'
        'BloqueadoAppx'
    } else {
        'BloqueadoFalhaPreVerificacao'
    }

    if ($script:Session) {
        $jsonSaida = Save-SysprepPreparationReport `
            -Session             $script:Session `
            -Ambiente            $ambiente `
            -Resultados          @() `
            -SysprepEstado       $estadoFalha `
            -SysprepBloqueado    $true `
            -SysprepBloqueadores @($ambiente.SysprepBlockers) `
            -MachineSid          $machineSid
        Write-SysprepLog -Message "Relatorio gravado: $jsonSaida"
    }

    Write-SysprepLog -Message "Pre-verificacao falhou ($estadoFalha). Encerrando."
    exit 1
}

Write-Ok "Sistema: $($ambiente.OsVersion) (build $($ambiente.BuildNumber))"

if ($ambiente.BuildNumber -gt 0 -and $ambiente.BuildNumber -lt 22000) {
    Write-Warn "Windows 10 detectado. Os tweaks sao compativeis; alguns podem nao ter efeito em versoes anteriores ao Windows 11."
    Write-SysprepLog -Level 'WARN' -Message "Windows 10 detectado (build $($ambiente.BuildNumber))."
}

Write-SysprepLog -Message "Pre-verificacao concluida. SO: $($ambiente.OsVersion) (build $($ambiente.BuildNumber))."

# ─── fase simulacao (sempre executada) ───────────────────────────────────────

Write-Section 'Simulacao - Tweaks a aplicar no Perfil Default'

$simulados = @(Invoke-SysprepPreparation -RegFilesDirectory $regfilesSysprepDir -DryRun)

foreach ($s in $simulados) {
    Write-Info "  [TWEAK]  $($s.Tweak)"
}
Write-Info '  [BACKUP] Copia de seguranca do NTUSER.DAT criada antes das modificacoes'
if ($autoLogonEncontrado) {
    Write-Info '  [AUTOLOGON] AutoAdminLogon=0 e DefaultPassword removido do registro Winlogon'
}
if ($gpoEncontrado) {
    Write-Info '  [GPO] Chaves de diretiva de grupo removidas (HKLM:\SOFTWARE\Policies e CurrentVersion\Policies)'
}
Write-Info '  [SECEDIT] Politica de seguranca local resetada para padrao Windows (sem complexidade de senha)'
if (-not $SemSysprep) {
    Write-Info '  [APPX] Pacotes Appx bloqueadores (ex: LanguageExperiencePack PT-BR) removidos para todos os usuarios antes do Sysprep'
    if ($IgnorarBloqueadoresAppx -and $IgnorarBloqueadoresAppx.Count -gt 0) {
        Write-Info "  [APPX] Ignorados (sem remocao, Sysprep liberado): $($IgnorarBloqueadoresAppx -join ', ')"
    }
    Write-Info '  [SYSPREP] sysprep.exe /oobe /generalize /shutdown  (somente apos confirmacao separada)'
}

Write-Host ''
Write-Info "$($simulados.Count) tweak(s) serao aplicados ao perfil Default."

if ($ApenasDryRun) {
    Write-SysprepLog -Message 'Modo ApenasDryRun: simulacao concluida. Nenhuma alteracao realizada.'
    Write-Ok 'Simulacao concluida. Nenhuma alteracao foi feita no sistema.'
    exit 0
}

# ─── confirmacao ─────────────────────────────────────────────────────────────

Write-Section 'Confirmacao'
Write-Warn 'ATENCAO: As modificacoes serao aplicadas ao perfil Default do Windows.'
Write-Warn 'Todos os usuarios criados apos este ponto herdarao as configuracoes listadas acima.'
Write-Warn 'Um backup do NTUSER.DAT sera criado automaticamente antes de qualquer alteracao.'
Write-Host ''

$confirmacao = if ($Confirmar) {
    Write-SysprepLog -Message 'Confirmacao automatica via -Confirmar.'
    'CONFIRMAR'
} else {
    Read-UserInput -Question 'Digite CONFIRMAR para prosseguir (qualquer outra entrada cancela)'
}

if ($confirmacao -ne 'CONFIRMAR') {
    Write-SysprepLog -Message 'Operacao cancelada pelo operador na etapa de confirmacao.'
    Write-Info 'Operacao cancelada. Nenhuma alteracao foi feita.'
    exit 0
}

Write-SysprepLog -Message 'Confirmacao recebida. Iniciando aplicacao dos tweaks.'

# ─── limpeza pre-sysprep ──────────────────────────────────────────────────────

if ($autoLogonEncontrado) {
    Write-Section 'Desativando AutoLogon'
    $winlogonReg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty -Path $winlogonReg -Name 'AutoAdminLogon' -Value '0' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $winlogonReg -Name 'DefaultPassword' -ErrorAction SilentlyContinue
    Write-Ok 'AutoLogon desativado (AutoAdminLogon=0). Senha removida do registro.'
    Write-SysprepLog -Message 'AutoLogon desativado e DefaultPassword removido.'
}

if ($gpoEncontrado) {
    Write-Section 'Removendo diretivas de grupo do registro'
    $gpoCaminhos = @(
        'HKLM:\SOFTWARE\Policies\Microsoft',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'
    )
    foreach ($gpoPath in $gpoCaminhos) {
        if (Test-Path -LiteralPath $gpoPath) {
            Remove-Item -LiteralPath $gpoPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Removido: $gpoPath"
            Write-SysprepLog -Message "Chave de diretiva removida: $gpoPath"
        }
    }
}

# A politica de seguranca local (secedit) persiste apos a limpeza do registry e
# sobrevive ao Sysprep. Resetar sempre com defltbase.inf garante que restricoes
# de senha e outras politicas nao bloqueiem o OOBE da imagem generalizada.
Write-Section 'Resetando politica de seguranca local'
$defltBase = Join-Path $env:SystemRoot 'inf\defltbase.inf'
$sdbPath   = Join-Path $env:TEMP "wba_secedit_$([System.Guid]::NewGuid().ToString('N')).sdb"
try {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $saida = & secedit /configure /cfg $defltBase /db $sdbPath /areas SECURITYPOLICY /quiet 2>&1
    $seceditExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($seceditExit -ne 0) {
        Write-Warn "secedit falhou ao resetar politica de seguranca (codigo $seceditExit)."
        Write-SysprepLog -Level 'WARN' -Message "secedit /configure falhou (codigo $seceditExit): $($saida -join ' ')"
    }
    else {
        Write-Ok 'Politica de seguranca local resetada para valores padrao (sem complexidade de senha).'
        Write-SysprepLog -Message 'Local Security Policy resetada via secedit defltbase.inf.'
    }
}
finally {
    Remove-Item -LiteralPath $sdbPath -Force -ErrorAction SilentlyContinue
}

# ─── fase execucao ────────────────────────────────────────────────────────────

Write-Section 'Aplicando tweaks ao Perfil Default'

$resultados = @(
    Invoke-SysprepPreparation `
        -RegFilesDirectory $regfilesSysprepDir `
        -BackupsPath $script:Session.BackupsPath
)

foreach ($r in $resultados) {
    $nivel = if ($r.Success) { 'INFO' } else { 'WARN' }
    Write-SysprepLog -Level $nivel -Message "$($r.Tweak): $($r.Message)"
}

$aplicados = @($resultados | Where-Object { $_.Success })
$falhos    = @($resultados | Where-Object { -not $_.Success })

Write-Host ''
Write-Info "$($aplicados.Count) tweak(s) aplicado(s) com sucesso."

if ($falhos.Count -gt 0) {
    Write-Warn "$($falhos.Count) tweak(s) com falha. Consulte o log: $(Join-Path $script:Session.LogsPath 'preparar-imagem.log')"
}

# ─── bloqueio por falha de tweak (Fase 2) ────────────────────────────────────

if ($falhos.Count -gt 0) {
    Write-Fail "$($falhos.Count) tweak(s) falharam. Sysprep bloqueado para evitar imagem incompleta."
    Write-Fail 'Corrija as falhas e execute novamente antes de generalizar o sistema.'
    Write-SysprepLog -Level 'ERROR' -Message "Sysprep bloqueado: $($falhos.Count) tweak(s) falharam."

    $jsonSaida = Save-SysprepPreparationReport `
        -Session          $script:Session `
        -Ambiente         $ambiente `
        -Resultados       $resultados `
        -SysprepEstado    'BloqueadoFalhaTweaks' `
        -SysprepBloqueado $true `
        -MachineSid       $machineSid
    Write-SysprepLog -Message "Relatorio gravado: $jsonSaida"
    Write-Ok "Relatorio JSON: $jsonSaida"
    Write-Title "Sessao encerrada com falha: $($script:Session.Path)"
    exit 1
}

# ─── sysprep.exe ─────────────────────────────────────────────────────────────

$sysprepEstado    = 'NaoSolicitado'
$sysprepExecutado = $false
$sysprepExitCode  = $null

if ($SemSysprep) {
    $sysprepEstado = 'IgnoradoPorParametro'
    Write-Info 'Sysprep ignorado por -SemSysprep.'
    Write-SysprepLog -Message 'Sysprep ignorado por parametro -SemSysprep.'
}
else {
    Write-Section 'Execucao do sysprep.exe'
    Write-Warn 'O sysprep.exe ira DESLIGAR o sistema apos a generalizacao.'
    Write-Warn 'Salve todos os arquivos abertos antes de confirmar.'
    Write-Host ''

    $executarSysprep = if ($ConfirmarSysprep) {
        Write-SysprepLog -Message 'Sysprep confirmado automaticamente via -ConfirmarSysprep.'
        $true
    } else {
        Read-YesNo `
            -Question 'Executar sysprep.exe /oobe /generalize /shutdown agora?' `
            -DefaultYes:$false
    }

    if ($executarSysprep) {
        $sysprepExe = [System.IO.Path]::Combine(
            [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System),
            'Sysprep',
            'sysprep.exe'
        )
        Write-Section 'Removendo pacotes Appx bloqueadores'
        Write-SysprepLog -Message 'Verificando e removendo pacotes Appx bloqueadores antes do Sysprep.'
        $appxPreRemocao = Test-SysprepEnvironment -AppxPolicy 'Warn'
        if ($appxPreRemocao.SysprepBlockers -and $appxPreRemocao.SysprepBlockers.Count -gt 0) {
            foreach ($bloqueador in $appxPreRemocao.SysprepBlockers) {
                if ($IgnorarBloqueadoresAppx -and ($bloqueador.Name -in $IgnorarBloqueadoresAppx)) {
                    Write-Warn "Appx bloqueador ignorado por -IgnorarBloqueadoresAppx: $($bloqueador.Name)"
                    Write-SysprepLog -Level 'WARN' -Message "Appx ignorado por parametro (Sysprep liberado): $($bloqueador.PackageFullName)"
                    continue
                }
                Write-SysprepLog -Message "Removendo Appx bloqueador: $($bloqueador.PackageFullName)"
                try {
                    Remove-AppxPackage -Package $bloqueador.PackageFullName -AllUsers -ErrorAction Stop
                    Write-Ok "Removido: $($bloqueador.Name)"
                    Write-SysprepLog -Message "Appx removido: $($bloqueador.PackageFullName)"
                }
                catch {
                    Write-Warn "Nao foi possivel remover $($bloqueador.Name): $($_.Exception.Message)"
                    Write-SysprepLog -Level 'WARN' -Message "Falha ao remover Appx $($bloqueador.PackageFullName): $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Ok 'Nenhum pacote Appx bloqueador encontrado.'
            Write-SysprepLog -Message 'Nenhum pacote Appx bloqueador encontrado para remover.'
        }

        Write-SysprepLog -Message 'Validando bloqueadores Appx antes de iniciar sysprep.exe.'
        $validacaoSysprep = Test-SysprepEnvironment -AppxPolicy 'Block'

        # Cada bloqueador Appx adiciona exatamente um erro em Test-SysprepEnvironment.
        # Subtrair a contagem de ignorados revela se ha erros remanescentes reais.
        $bloqueadoresIgnoradosCount = if ($IgnorarBloqueadoresAppx -and $validacaoSysprep.SysprepBlockers) {
            @($validacaoSysprep.SysprepBlockers | Where-Object { $_.Name -in $IgnorarBloqueadoresAppx }).Count
        } else { 0 }
        $errosRemanescentes = $validacaoSysprep.Errors.Count - $bloqueadoresIgnoradosCount
        $validoEfetivo = $validacaoSysprep.IsValid -or ($errosRemanescentes -eq 0)

        if (-not $validoEfetivo) {
            foreach ($erro in $validacaoSysprep.Errors) {
                Write-SysprepLog -Level 'ERROR' -Message $erro
            }

            $sysprepEstado = if ($validacaoSysprep.SysprepBlockers -and $validacaoSysprep.SysprepBlockers.Count -gt 0) {
                Write-Fail 'Sysprep bloqueado: existem pacotes Appx instalados para usuario, mas nao provisionados para todos os usuarios.'
                Write-Fail 'Corrija os bloqueadores Appx antes de generalizar a imagem.'
                'BloqueadoAppx'
            }
            else {
                Write-Fail 'Sysprep bloqueado: a pre-verificacao obrigatoria falhou.'
                'BloqueadoFalhaPreVerificacao'
            }

            $jsonSaida = Save-SysprepPreparationReport `
                -Session              $script:Session `
                -Ambiente             $validacaoSysprep `
                -Resultados           $resultados `
                -SysprepEstado        $sysprepEstado `
                -SysprepBloqueado     $true `
                -SysprepBloqueadores  @($validacaoSysprep.SysprepBlockers) `
                -MachineSid           $machineSid
            Write-SysprepLog -Message "Relatorio gravado: $jsonSaida"
            Write-Ok "Relatorio JSON: $jsonSaida"
            Write-Title "Sessao encerrada com bloqueio: $($script:Session.Path)"
            exit 1
        }

        Write-SysprepLog -Message 'Iniciando sysprep.exe /oobe /generalize /shutdown.'
        Write-Warn 'Executando sysprep.exe. O sistema sera desligado em instantes...'

        $sysprepEstado    = 'Iniciado'
        $sysprepExecutado = $true
        $processo = Start-Process -FilePath $sysprepExe `
            -ArgumentList '/oobe /generalize /shutdown' `
            -Wait -PassThru
        $sysprepExitCode = $processo.ExitCode
        Write-SysprepLog -Message "sysprep.exe encerrado com ExitCode: $sysprepExitCode."

        if ($sysprepExitCode -eq 0) {
            $sysprepEstado = 'Concluido'
        }
        else {
            $sysprepEstado = 'Falhou'
            Write-Fail "sysprep.exe falhou com ExitCode $sysprepExitCode."
            Write-Fail 'Verifique C:\Windows\System32\Sysprep\Panther\setuperr.log'
            Write-SysprepLog -Level 'ERROR' -Message "Sysprep falhou. Verifique C:\Windows\System32\Sysprep\Panther\setuperr.log"
        }
    }
    else {
        $sysprepEstado = 'IgnoradoPeloOperador'
        Write-Info 'Execucao do sysprep.exe ignorada. Execute manualmente quando pronto.'
        Write-SysprepLog -Message 'Execucao do sysprep.exe ignorada pelo operador.'
    }
}

# ─── relatorio ───────────────────────────────────────────────────────────────

Write-Section 'Relatorio da sessao'

$jsonPath = Save-SysprepPreparationReport `
    -Session             $script:Session `
    -Ambiente            $ambiente `
    -Resultados          $resultados `
    -SysprepEstado       $sysprepEstado `
    -SysprepExecutado    $sysprepExecutado `
    -SysprepExitCode     $sysprepExitCode `
    -SysprepBloqueadores @($ambiente.SysprepBlockers) `
    -MachineSid          $machineSid

Write-SysprepLog -Message 'Sessao encerrada.'
Write-Ok "Relatorio JSON: $jsonPath"
Write-Title "Sessao concluida: $($script:Session.Path)"

if ($sysprepEstado -eq 'Falhou') {
    exit $sysprepExitCode
}
