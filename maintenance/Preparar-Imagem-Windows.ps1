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

# ─── inicializacao ───────────────────────────────────────────────────────────

Write-Title "WBA Windows Toolkit - Preparacao de Imagem Windows $ScriptVersion"

if ($ApenasDryRun) {
    Write-Warn 'MODO APENAS DRY-RUN: nenhuma alteracao sera feita no sistema.'
}

$script:Session = Initialize-ScriptSession `
    -ModuleName 'WbaToolkit.Maintenance' `
    -BasePath $Path `
    -ExecutionMode 'Preparacao'

Write-SysprepLog -Message "Sessao iniciada. ApenasDryRun: $ApenasDryRun. SemSysprep: $SemSysprep."
Write-Info "Relatorios em: $($script:Session.Path)"

# ─── pre-verificacao ──────────────────────────────────────────────────────────

Write-Section 'Verificacao de pre-requisitos'

$ambiente = Test-SysprepEnvironment

foreach ($aviso in $ambiente.Warnings) {
    Write-Warn $aviso
    Write-SysprepLog -Level 'WARN' -Message $aviso
}

if (-not $ambiente.IsValid) {
    foreach ($erro in $ambiente.Errors) {
        Write-Fail $erro
        Write-SysprepLog -Level 'ERROR' -Message $erro
    }
    Write-SysprepLog -Message 'Pre-verificacao falhou. Encerrando.'
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
if (-not $SemSysprep) {
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

$confirmacao = Read-UserInput -Question 'Digite CONFIRMAR para prosseguir (qualquer outra entrada cancela)'

if ($confirmacao -ne 'CONFIRMAR') {
    Write-SysprepLog -Message 'Operacao cancelada pelo operador na etapa de confirmacao.'
    Write-Info 'Operacao cancelada. Nenhuma alteracao foi feita.'
    exit 0
}

Write-SysprepLog -Message 'Confirmacao recebida. Iniciando aplicacao dos tweaks.'

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

# ─── sysprep.exe ─────────────────────────────────────────────────────────────

if (-not $SemSysprep) {
    Write-Section 'Execucao do sysprep.exe'
    Write-Warn 'O sysprep.exe ira DESLIGAR o sistema apos a generalizacao.'
    Write-Warn 'Salve todos os arquivos abertos antes de confirmar.'
    Write-Host ''

    $executarSysprep = Read-YesNo `
        -Question 'Executar sysprep.exe /oobe /generalize /shutdown agora?' `
        -DefaultYes:$false

    if ($executarSysprep) {
        $sysprepExe = [System.IO.Path]::Combine(
            [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System),
            'Sysprep',
            'sysprep.exe'
        )
        Write-SysprepLog -Message 'Iniciando sysprep.exe /oobe /generalize /shutdown.'
        Write-Warn 'Executando sysprep.exe. O sistema sera desligado em instantes...'
        Start-Process -FilePath $sysprepExe -ArgumentList '/oobe /generalize /shutdown' -Wait
    }
    else {
        Write-Info 'Execucao do sysprep.exe ignorada. Execute manualmente quando pronto.'
        Write-SysprepLog -Message 'Execucao do sysprep.exe ignorada pelo operador.'
    }
}

# ─── relatorio ───────────────────────────────────────────────────────────────

Write-Section 'Relatorio da sessao'

$relatorio = [pscustomobject]@{
    Inicio       = $script:Session.StartedAt
    Fim          = Get-Date
    Modo         = $script:Session.Mode
    ApenasDryRun = [bool]$ApenasDryRun
    SemSysprep   = [bool]$SemSysprep
    ComputerName = $env:COMPUTERNAME
    OsVersion    = $ambiente.OsVersion
    BuildNumber  = $ambiente.BuildNumber
    Tweaks       = @($resultados)
}

$jsonPath = Join-Path $script:Session.Path 'relatorio-preparacao-imagem.json'
$relatorio | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath

Write-SysprepLog -Message 'Sessao encerrada.'
Write-Ok "Relatorio JSON: $jsonPath"
Write-Title "Sessao concluida: $($script:Session.Path)"
