#requires -version 5.1

# BCK-065: regras amplas do .gitignore nao podem esconder codigo do toolkit.

BeforeDiscovery {
    $script:gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe 'Regras do .gitignore' -Skip:(-not $script:gitAvailable) {
    It 'Nao ignora arquivos do modulo WbaToolkit.Backup, mesmo com core.ignorecase' {
        & git -C $script:repoRoot -c core.ignorecase=true check-ignore -q --no-index -- 'modules/WbaToolkit.Backup/Public/Novo.ps1'
        $LASTEXITCODE | Should -Be 1
    }

    It 'Continua ignorando arquivos *.backup comuns' {
        & git -C $script:repoRoot check-ignore -q --no-index -- 'qualquer/arquivo.backup'
        $LASTEXITCODE | Should -Be 0
    }
}
