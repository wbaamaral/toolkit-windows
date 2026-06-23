#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $repoRoot = Get-XtudoRepoRoot
    $script:launcherContent = Get-XtudoLauncherContent
    $script:connectivityContent = Get-Content -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'testar-conectividade-internet.ps1') -Raw
    $script:hardwareContent = Get-Content -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'verificar-atualizacoes-hardware.ps1') -Raw
    $script:connectivityModuleContent = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1') -Raw
    $script:coreModuleContent = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Raw
}

Describe 'Xtudo rotas de rede' {
    It 'Mantem os scripts oficiais de rede em scripts/' {
        Test-Path -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'testar-conectividade-internet.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'verificar-atualizacoes-hardware.ps1') | Should -BeTrue
        $script:connectivityContent | Should -Match 'WbaToolkit\.Networking\.psd1'
        $script:hardwareContent | Should -Match 'WbaToolkit\.Core\.psd1'
        $script:connectivityModuleContent | Should -Match 'RootModule'
        $script:coreModuleContent | Should -Match 'RootModule'
    }

    It 'Nao referencia experimental nos scripts oficiais de rede' {
        $script:connectivityContent | Should -Not -Match 'experimental/'
        $script:hardwareContent | Should -Not -Match 'experimental/'
    }

    It 'Mantem atualização pesquisavel no launcher' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/atualizar-windows\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Atualizar Windows'"
        $script:launcherContent | Should -Match "Keywords\s+=\s+@\('atualizar', 'update', 'windows update', 'winget', 'chocolatey'\)"
    }
}
