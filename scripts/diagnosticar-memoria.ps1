#!/usr/bin/env pwsh
#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$target = Join-Path $PSScriptRoot '../diagnostics/Diagnostico-Memoria.ps1'
& $target @RemainingArgs
