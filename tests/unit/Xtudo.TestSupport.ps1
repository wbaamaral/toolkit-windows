#requires -version 5.1

function Get-XtudoRepoRoot {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Get-XtudoLauncherPath {
    Join-Path (Get-XtudoRepoRoot) 'xtudo.ps1'
}

function Get-XtudoLauncherContent {
    Get-Content -LiteralPath (Get-XtudoLauncherPath) -Raw
}

function Get-XtudoScriptsRoot {
    Join-Path (Get-XtudoRepoRoot) 'scripts'
}

function Get-XtudoOfficialScriptPaths {
    Get-ChildItem -LiteralPath (Get-XtudoScriptsRoot) -File -Filter '*.ps1' |
        Sort-Object Name |
        Select-Object -ExpandProperty FullName
}

function Get-XtudoExperimentalPaths {
    Get-ChildItem -LiteralPath (Join-Path (Get-XtudoRepoRoot) 'experimental') -Recurse -File -Filter '*.ps1' |
        Sort-Object FullName |
        Select-Object -ExpandProperty FullName
}
