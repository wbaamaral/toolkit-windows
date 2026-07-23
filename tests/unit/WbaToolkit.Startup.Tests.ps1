#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:launcherContent = Get-XtudoLauncherContent
}

Describe 'Xtudo fluxo do operador' {
    It 'Permite cancelar e sair sem acionar script' {
        $script:launcherContent | Should -Match '0/q/sair cancela'
        $script:launcherContent | Should -Match "\$input -match '\^\(0\|q\|quit\|sair\)\$'"
        $script:launcherContent | Should -Match 'break'
    }

    It 'Mantem busca por palavra-chave no launcher' {
        $script:launcherContent | Should -Match 'Select-XtudoEntry -Entries \$catalog -Tokens @\(\$input\)'
        $script:launcherContent | Should -Match 'Resultados encontrados:'
        $script:launcherContent | Should -Match 'Nenhum resultado exato\.'
    }

    It 'Expõe a rota oficial de gerenciamento de inicialização' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/gerenciar-inicializacao\.ps1'"
        $script:launcherContent | Should -Match "Category\s+=\s+'Inicialização'"
    }
}
