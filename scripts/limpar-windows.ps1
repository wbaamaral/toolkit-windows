#!/usr/bin/env pwsh
#requires -version 5.1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
try { chcp 65001 | Out-Null } catch { }
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
