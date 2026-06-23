#!/usr/bin/env pwsh
#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$target = Join-Path $PSScriptRoot '../maintenance/Diagnostico-Reparo-HD100.ps1'
& $target @RemainingArgs
