#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:launcherPath = Get-XtudoLauncherPath
    $script:launcherContent = Get-XtudoLauncherContent
}

Describe 'Xtudo launcher' {
    It 'Mantem o ponto unico de entrada do operador' {
        Test-Path -LiteralPath $script:launcherPath | Should -BeTrue
        $script:launcherContent | Should -Match 'Launcher principal do WBA Windows Toolkit'
        $script:launcherContent | Should -Match 'pasta scripts/'
    }

    It 'Expõe os blocos de rotina esperados do portal' {
        $script:launcherContent | Should -Match 'function\s+New-XtudoCatalog'
        $script:launcherContent | Should -Match 'function\s+Get-XtudoEntry'
        $script:launcherContent | Should -Match 'function\s+Select-XtudoEntry'
        $script:launcherContent | Should -Match 'function\s+Invoke-XtudoScript'
    }

    It 'Mantem cinco atalhos rapidos, busca e rotas pesquisaveis adicionais' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/limpar-windows\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-disco-100\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-memoria\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-grafico\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/preparar-imagem-windows\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/atualizar-windows\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-ad-cliente\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/inventario-hardware-software\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Inventário hardware e software'"
        $script:launcherContent | Should -Match "Category\s+=\s+'Inventário'"
        ($script:launcherContent -match 'Quick\s+=\s+\$true') | Should -BeTrue
        $script:launcherContent | Should -Match '0/q/sair cancela'
        $script:launcherContent | Should -Match "\$input -match '\^\(0\|q\|quit\|sair\)\$'"
        $script:launcherContent | Should -Match 'Resultados encontrados:'
        $script:launcherContent | Should -Match 'Nenhum resultado exato\.'
    }

    It 'Normaliza argumentos antes de chamar scripts' {
        $script:launcherContent | Should -Match 'foreach \(\$arg in @\(\$Entry\.Args\)\)'
        $script:launcherContent | Should -Match '\$text = \[string\]\$arg'
        $script:launcherContent | Should -Match '\$text -match ''\^\\-\\S\+\\s\+\\S\+\$'''
        $script:launcherContent | Should -Match '\$invokeArgs \+= @\(\$text -split ''\\s\+'', 2\)'
    }
}
