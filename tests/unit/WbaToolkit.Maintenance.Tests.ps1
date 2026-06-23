#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:launcherContent = Get-XtudoLauncherContent
    $script:cleanupPath = Join-Path (Get-XtudoScriptsRoot) 'limpar-windows.ps1'
    $script:diskPath = Join-Path (Get-XtudoScriptsRoot) 'diagnosticar-disco-100.ps1'
    $script:imagePath = Join-Path (Get-XtudoScriptsRoot) 'preparar-imagem-windows.ps1'
    $script:winsxsPath = Join-Path (Get-XtudoScriptsRoot) 'limpar-winsxs.ps1'
    $script:cleanupContent = Get-Content -LiteralPath $script:cleanupPath -Raw
    $script:diskContent = Get-Content -LiteralPath $script:diskPath -Raw
    $script:imageContent = Get-Content -LiteralPath $script:imagePath -Raw
    $script:winsxsContent = Get-Content -LiteralPath $script:winsxsPath -Raw
}

Describe 'Xtudo rotas de manutencao' {
    It 'Mantem os scripts oficiais de manutencao em scripts/' {
        Test-Path -LiteralPath $script:cleanupPath | Should -BeTrue
        Test-Path -LiteralPath $script:diskPath | Should -BeTrue
        Test-Path -LiteralPath $script:imagePath | Should -BeTrue
        Test-Path -LiteralPath $script:winsxsPath | Should -BeTrue
    }

    It 'Nao referencia experimental nos scripts oficiais de manutencao' {
        $script:cleanupContent | Should -Not -Match 'experimental/'
        $script:diskContent | Should -Not -Match 'experimental/'
        $script:imageContent | Should -Not -Match 'experimental/'
        $script:winsxsContent | Should -Not -Match 'experimental/'
    }

    It 'Mantem importacao compartilhada e parametros esperados nos scripts de manutencao' {
        $script:cleanupContent | Should -Match 'WbaToolkit\.Core\.psd1'
        $script:cleanupContent | Should -Match 'WbaToolkit\.Maintenance\.psd1'
        $script:cleanupContent | Should -Match 'ChkdskAction'
        $script:cleanupContent | Should -Match 'EventLogCleanup'

        $script:diskContent | Should -Match 'WbaToolkit\.Core\.psd1'
        $script:diskContent | Should -Match 'WbaToolkit\.Startup\.psd1'
        $script:diskContent | Should -Match "ValidateSet\('Diagnostico', 'Assistido', 'Relatorio', 'Rollback'\)"

        $script:imageContent | Should -Match 'WbaToolkit\.Core\.psd1'
        $script:imageContent | Should -Match 'WbaToolkit\.Maintenance\.psd1'
        $script:imageContent | Should -Match 'CONFIRMAR'
        $script:imageContent | Should -Match 'SemSysprep'

        $script:winsxsContent | Should -Match 'WbaToolkit\.Core\.psd1'
        $script:winsxsContent | Should -Match 'WbaToolkit\.Maintenance\.psd1'
    }

    It 'Mantem a limpeza do Windows como atalho do MVP no launcher' {
        $script:launcherContent | Should -Match "Label\s+=\s+'Limpar Windows'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/limpar-windows\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Diagnosticar disco 100%'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-disco-100\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Preparar imagem'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/preparar-imagem-windows\.ps1'"
    }
}
