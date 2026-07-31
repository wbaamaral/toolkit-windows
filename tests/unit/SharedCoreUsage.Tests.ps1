#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:scriptPaths = @(Get-XtudoOfficialScriptPaths)
    $script:repoRoot = Get-XtudoRepoRoot
    $script:operatorManualContent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/README.md') -Raw
}

Describe 'Xtudo estrutura do toolkit' {
    It 'Mantem vinte e seis scripts oficiais em scripts/' {
        $script:scriptPaths.Count | Should -Be 26
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

    It 'Nao usa Import-Module por variavel para dependencias do toolkit' {
        foreach ($path in $script:scriptPaths) {
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Not -Match '(?im)^\s*Import-Module\s+\$[A-Za-z_][A-Za-z0-9_]*'
        }
    }

    It 'Carrega dependencias do toolkit por dot-source com verificacao de caminho' {
        foreach ($path in $script:scriptPaths) {
            $content = Get-Content -LiteralPath $path -Raw
            if ($content -match 'modules/WbaToolkit\.') {
                $content | Should -Match 'Test-Path\s+-LiteralPath'
                $content | Should -Match 'Get-ChildItem\s+-LiteralPath\s+\$[A-Za-z_][A-Za-z0-9_]*\s+-Filter\s+''\*\.ps1''\s+-File'
                $content | Should -Match 'ForEach-Object\s+\{\s*\.\s+\$_.FullName\s*\}'
            }
        }
    }

    It 'A documentacao continua apontando para o launcher xtudo' {
        (Get-Content -LiteralPath (Join-Path $script:repoRoot 'README.md') -Raw) | Should -Match '\.\\xtudo\.ps1'
        (Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/README.md') -Raw) | Should -Match '\.\\xtudo\.ps1'
    }

    It 'Os manuais do operador destacam o MVP oficial atual' {
        $script:operatorManualContent | Should -Match 'scripts\\limpar-windows\.ps1'
        $script:operatorManualContent | Should -Match 'scripts\\atualizar-windows\.ps1'
        $script:operatorManualContent | Should -Match 'scripts\\diagnosticar-ad-cliente\.ps1'
        $script:operatorManualContent | Should -Match 'scripts\\inventario-hardware-software\.ps1'
        $script:operatorManualContent | Should -Match 'scripts\\detectar-ip-duplicado\.ps1'
        $script:operatorManualContent | Should -Match 'WbaToolkit\.Licensing'
    }
}
