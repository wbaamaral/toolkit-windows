#!/usr/bin/env pwsh
#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$target = Join-Path $PSScriptRoot '../maintenance/Limpeza-WinSxS.ps1'
& $target @RemainingArgs
