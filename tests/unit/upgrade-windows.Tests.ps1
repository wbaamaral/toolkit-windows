#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:launcherContent = Get-XtudoLauncherContent
    $script:updatePath = Join-Path (Get-XtudoScriptsRoot) 'atualizar-windows.ps1'
    $script:updateContent = Get-Content -LiteralPath $script:updatePath -Raw
}

Describe 'Xtudo rotas de update' {
    It 'Mantem o script oficial de update em scripts/' {
        Test-Path -LiteralPath $script:updatePath | Should -BeTrue
        $script:updateContent | Should -Match 'WbaToolkit\.Core\.psd1'
        $script:updateContent | Should -Match "ValidateSet\('Auto', 'WinGet', 'Chocolatey', 'All'\)"
        $script:updateContent | Should -Match 'Invoke-WindowsUpdateStep'
    }

    It 'Nao referencia experimental no script oficial de update' {
        $script:updateContent | Should -Not -Match 'experimental/'
    }

    It 'Exibe update como rota pesquisavel no launcher' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/atualizar-windows\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Atualizar Windows'"
        $script:launcherContent | Should -Match "Keywords\s+=\s+@\('atualizar', 'update', 'windows update', 'winget', 'chocolatey'\)"
    }
}
