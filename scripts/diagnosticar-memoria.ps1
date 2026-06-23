<#
.SYNOPSIS
    Atalho para diagnostico de memoria.

.DESCRIPTION
    Encaminha a execução para o script operacional de diagnostico de RAM.

.EXAMPLE
    .\scripts\diagnosticar-memoria.ps1
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

$target = Join-Path $PSScriptRoot '../diagnostics/Diagnostico-Memoria.ps1'
$forwardArgs = if ($args.Count -gt 0) { $args } else { @() }
& $target @forwardArgs
