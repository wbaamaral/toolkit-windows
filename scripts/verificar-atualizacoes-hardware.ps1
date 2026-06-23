<#
.SYNOPSIS
    Atalho para verificar atualizacoes de hardware.

.DESCRIPTION
    Encaminha a execução para o script operacional de inventario e updates.

.EXAMPLE
    .\scripts\verificar-atualizacoes-hardware.ps1
#>
#!/usr/bin/env pwsh
#requires -version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
try { chcp 65001 | Out-Null } catch { }

$target = Join-Path $PSScriptRoot '../experimental/diagnostics/Verificar-Atualizacoes-Hardware.ps1'
if ($args.Count -gt 0) {
    & $target @args
}
else {
    & $target
}
