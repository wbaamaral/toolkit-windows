#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:scriptPaths = @(Get-XtudoOfficialScriptPaths)
    $script:repoRoot = Get-XtudoRepoRoot
    $script:operatorGuideContent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'manuais/operador/guia-rapido.md') -Raw
    $script:operatorManualContent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'manuais/manual-operador-wba-windows-toolkit.md') -Raw
}

Describe 'Xtudo estrutura do toolkit' {
    It 'Mantem dezessete scripts oficiais em scripts/' {
        $script:scriptPaths.Count | Should -Be 17
        foreach ($path in $script:scriptPaths) {
            Split-Path -Parent $path | Should -Be (Get-XtudoScriptsRoot)
        }
    }

    It 'Nao referencia experimental nos scripts oficiais' {
        foreach ($path in $script:scriptPaths) {
            (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'experimental/'
        }
    }

    It 'Todos os scripts oficiais continuam parseando como PowerShell valido' {
        foreach ($path in $script:scriptPaths) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    It 'A documentacao continua apontando para o launcher xtudo' {
        (Get-Content -LiteralPath (Join-Path $script:repoRoot 'README.md') -Raw) | Should -Match '\.\\xtudo\.ps1'
        (Get-Content -LiteralPath (Join-Path $script:repoRoot 'manuais/README.md') -Raw) | Should -Match '\.\./xtudo\.ps1'
    }

    It 'Os manuais do operador destacam o MVP oficial atual' {
        $script:operatorGuideContent | Should -Match 'scripts\\limpar-windows\.ps1'
        $script:operatorGuideContent | Should -Match 'scripts\\atualizar-windows\.ps1'
        $script:operatorGuideContent | Should -Match 'scripts\\diagnosticar-ad-cliente\.ps1'
        $script:operatorGuideContent | Should -Match 'scripts\\Inventario-Hardware-Software\.ps1'
        $script:operatorManualContent | Should -Match 'diagnosticar-ad-cliente\.ps1'
        $script:operatorManualContent | Should -Match 'Legado experimental de AD'
    }
}
