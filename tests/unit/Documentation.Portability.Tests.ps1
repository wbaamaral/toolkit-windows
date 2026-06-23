#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot = Get-XtudoRepoRoot
    $script:functionDocsContent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'modules/WbaToolkit.Core/Public/Export-ToolkitFunctionDocs.ps1') -Raw
    $script:portalDocsContent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'modules/WbaToolkit.Core/Public/Export-ToolkitDocumentation.ps1') -Raw
}

Describe 'Xtudo portabilidade da documentacao de inventario' {
    It 'Resolve o inventario a partir da arvore real do repositório' {
        $script:functionDocsContent | Should -Match 'scripts/Inventario-Hardware-Software\.ps1'
        $script:portalDocsContent | Should -Match 'scripts/Inventario-Hardware-Software\.ps1'
        $script:functionDocsContent | Should -Match 'WbaToolkit.Inventory/WbaToolkit.Inventory\.psd1'
        $script:portalDocsContent | Should -Match 'WbaToolkit.Inventory/WbaToolkit.Inventory\.psd1'
    }

    It 'Nao depende do diretório atual para localizar os arquivos do portal' {
        $script:functionDocsContent | Should -Match 'Split-Path -Parent \(Split-Path -Parent \(Split-Path -Parent \$PSScriptRoot\)\)'
        $script:portalDocsContent | Should -Match 'Split-Path -Parent \(Split-Path -Parent \(Split-Path -Parent \$PSScriptRoot\)\)'
    }

    It 'Usa a raiz do repositório ao gerar o portal e a referência técnica' {
        $script:functionDocsContent | Should -Match 'scripts/Inventario-Hardware-Software\.ps1'
        $script:portalDocsContent | Should -Match 'scripts/Inventario-Hardware-Software\.ps1'
        $script:functionDocsContent | Should -Match 'WbaToolkit.Inventory/WbaToolkit.Inventory\.psd1'
        $script:portalDocsContent | Should -Match 'WbaToolkit.Inventory/WbaToolkit.Inventory\.psd1'
    }
}
