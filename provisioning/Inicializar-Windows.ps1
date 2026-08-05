#requires -version 5.1
<#
.SYNOPSIS
    Ponto de entrada da tarefa agendada de provisionamento inicial do Windows.

.DESCRIPTION
    Executado como NT AUTHORITY\SYSTEM pela tarefa '\WBA\Provisioning\Inicializar-Windows'
    a cada inicializacao do sistema (WbaToolkit.Provisioning, Fase 1 — ADR-0033). Decide
    entre continuar um deployment ja em andamento (Running/RebootPending/Planned em
    Work\<deploymentId>\state.json) ou iniciar um novo a partir da configuracao
    localizavel (Inbox ou midia removivel marcada).

    Nunca lanca excecao nao tratada: qualquer falha e registrada em Logs\ e o script
    encerra com codigo de saida distinto de zero, deixando o estado em disco intacto
    para diagnostico e retomada manual.

.PARAMETER ConfigPath
    Caminho explicito de configuracao. Uso principal: execucao manual para diagnostico.
    A tarefa agendada nao passa este parametro — usa a precedencia padrao.

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\Inicializar-Windows.ps1

    Uso normal, disparado pela tarefa agendada.

.EXAMPLE
    .\Inicializar-Windows.ps1 -ConfigPath C:\WBA\provisioning.json

    Execucao manual apontando uma configuracao especifica (requer sessao administrativa).

.NOTES
    Projeto: wba-toolkit
    Autor: wbaamaral
    Modulos WbaToolkit.Core e WbaToolkit.Provisioning sao carregados por dot-source (ADR 0032).
#>
param(
    [string]$ConfigPath,
    [switch]$Help
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$ToolkitRoot       = Split-Path -Parent $PSScriptRoot
$coreRoot          = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'
$provisioningRoot  = Join-Path $ToolkitRoot 'modules/WbaToolkit.Provisioning'

foreach ($dir in @($coreRoot, $provisioningRoot)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Host "[FALHA] Modulo nao encontrado: $dir" -ForegroundColor Red
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreRoot, $provisioningRoot)) {
        foreach ($sub in @('Private', 'Steps', 'Public')) {
            $subDir = Join-Path $moduleRoot $sub
            if (Test-Path -LiteralPath $subDir) {
                Get-ChildItem -LiteralPath $subDir -Filter '*.ps1' -File -Recurse |
                    ForEach-Object { . $_.FullName }
            }
        }
    }
}
catch {
    Write-Host '[FALHA] Nao foi possivel carregar os modulos do toolkit.' -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

$paths = Get-ToolkitProvisioningPaths
if (-not (Test-Path -LiteralPath $paths.Logs)) {
    New-Item -Path $paths.Logs -ItemType Directory -Force | Out-Null
}
$logFile = Join-Path $paths.Logs "inicializar-windows-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -Append | Out-Null

try {
    $pendingDeploymentId = $null
    if (Test-Path -LiteralPath $paths.Work) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $paths.Work -Directory -ErrorAction SilentlyContinue)) {
            $stateRead = Read-ToolkitProvisioningState -StateDirectory $dir.FullName
            if ($stateRead.Found -and $stateRead.State -and
                $stateRead.State.GlobalState -in @('Running', 'RebootPending', 'Planned')) {
                $pendingDeploymentId = $dir.Name
                break
            }
        }
    }

    if ($pendingDeploymentId) {
        Write-Info "Retomando deployment pendente: $pendingDeploymentId"
        $result = Resume-ToolkitProvisioning -DeploymentId $pendingDeploymentId
    }
    else {
        Write-Info 'Nenhum deployment pendente; procurando configuracao nova.'
        $result = Invoke-ToolkitProvisioning -ConfigPath $ConfigPath
    }

    Write-Info "Estado final: $($result.GlobalState); acao de reboot: $($result.RebootAction)"

    if ($result.GlobalState -eq 'Failed') {
        exit 2
    }
    exit 0
}
catch {
    Write-Fail "Execucao de provisionamento interrompida: $($_.Exception.Message)"
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
