#!/usr/bin/env bash
# Executa PSScriptAnalyzer sobre modules/ e scripts/ (ADR 0016, BCK-028).
# Falha (exit != 0) apenas em achados de severidade Error; avisos sao listados
# mas nao bloqueiam o gate (debito tecnico existente, ver BCK-029 e afins).
#
# Uso:
#   bash tools/lint-check.sh
#
# Dependencias:
#   pwsh (PowerShell 7) ou powershell (Windows PowerShell 5.1) no PATH
#   Modulo PSScriptAnalyzer (Install-Module PSScriptAnalyzer -Scope CurrentUser)

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PWSH_BIN="$(command -v pwsh || command -v powershell || true)"
if [[ -z "$PWSH_BIN" ]]; then
    echo "Erro: nem 'pwsh' nem 'powershell' encontrados no PATH." >&2
    exit 1
fi

echo "Executando PSScriptAnalyzer sobre modules/ e scripts/ ..."

"$PWSH_BIN" -NoProfile -ExecutionPolicy Bypass -Command - <<'PS_EOF'
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Error "Modulo PSScriptAnalyzer nao instalado. Instale com: Install-Module PSScriptAnalyzer -Scope CurrentUser"
    exit 2
}
Import-Module PSScriptAnalyzer

$results = @()
foreach ($target in 'modules', 'scripts') {
    $results += @(Invoke-ScriptAnalyzer -Path $target -Recurse)
}

$errs     = @($results | Where-Object Severity -eq 'Error')
$warnings = @($results | Where-Object Severity -eq 'Warning')

if ($warnings.Count -gt 0) {
    Write-Host "$($warnings.Count) aviso(s) do PSScriptAnalyzer (nao bloqueiam o gate):" -ForegroundColor Yellow
    $warnings | Sort-Object ScriptName, Line | Format-Table RuleName, ScriptName, Line -AutoSize | Out-String | Write-Host
}

if ($errs.Count -gt 0) {
    Write-Host "$($errs.Count) erro(s) do PSScriptAnalyzer:" -ForegroundColor Red
    $errs | Format-Table RuleName, ScriptName, Line, Message -AutoSize | Out-String | Write-Host
    exit 1
}

Write-Host "PSScriptAnalyzer: sem erros ($($warnings.Count) aviso(s) pendente(s))." -ForegroundColor Green
PS_EOF
