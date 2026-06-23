#!/usr/bin/env pwsh
#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$target = Join-Path $PSScriptRoot '../maintenance/limpeza-windows.ps1'

# O atalho do Xtudo precisa ser seguro e previsivel no modo MVP.
# Quando nao ha argumentos explicitos, usamos a trilha nao interativa
# recomendada para automacao.
$invokeArgs = if ($RemainingArgs -and $RemainingArgs.Count -gt 0) {
    @($RemainingArgs)
}
else {
    @('-ChkdskAction', 'Skip', '-EventLogCleanup', 'None', '-NoReboot')
}

& $target @invokeArgs
