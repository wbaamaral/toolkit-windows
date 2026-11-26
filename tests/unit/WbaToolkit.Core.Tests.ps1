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

    It 'Mantem cinco atalhos rapidos e rotas pesquisaveis oficiais' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/limpar-windows\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-disco-100\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-memoria\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-grafico\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/preparar-imagem-windows\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/atualizar-windows\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-ad-cliente\.ps1'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/inventario-hardware-software\.ps1'"
        ($script:launcherContent -match 'Quick\s+=\s+\$true') | Should -BeTrue
    }

    It 'Preserva os atalhos de cancelamento para o operador' {
        $script:launcherContent | Should -Match '0/q/sair cancela'
        ($script:launcherContent.Contains("`$input -match '^(0|q|quit|sair)$'")) | Should -BeTrue
    }
}

Describe 'Test-ToolkitLabMock (BCK-065: mocks do lab fora de producao)' {
    BeforeAll {
        $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $root 'modules/WbaToolkit.Core/Public/Test-ToolkitLabMock.ps1')
        $script:savedMock = $env:WBA_MOCK_AD
    }

    AfterAll {
        $env:WBA_MOCK_AD = $script:savedMock
    }

    It 'Sem WBA_MOCK_AD nunca habilita mocks' {
        $env:WBA_MOCK_AD = $null
        Test-ToolkitLabMock | Should -BeFalse
    }

    It 'Com WBA_MOCK_AD so habilita fora do Windows' {
        $env:WBA_MOCK_AD = '1'
        $isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
        Test-ToolkitLabMock | Should -Be (-not $isWindowsPlatform)
    }

    It 'Nenhum modulo ou script consulta WBA_MOCK_AD sem o gate ou sem exigir Linux' {
        $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $violacoes = @(Get-ChildItem (Join-Path $root 'modules'), (Join-Path $root 'scripts') -Recurse -File |
            Where-Object { $_.Extension -in @('.ps1', '.psm1') -and $_.Name -ne 'Test-ToolkitLabMock.ps1' } |
            Select-String -Pattern '\$env:WBA_MOCK_AD' |
            Where-Object { $_.Line -notmatch '^\s*#' -and $_.Line -notmatch '\$IsLinux' })
        ($violacoes | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) | Should -BeNullOrEmpty
    }
}
