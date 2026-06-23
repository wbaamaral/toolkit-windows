#!/usr/bin/env pwsh
#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$target = Join-Path $PSScriptRoot '../diagnostics/networking/Testar-Conectividade-Internet.ps1'
& $target @RemainingArgs
