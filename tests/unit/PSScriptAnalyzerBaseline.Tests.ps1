#requires -version 5.1

Describe 'Baseline do PSScriptAnalyzer' {
    It 'documenta as excecoes de UI associadas ao BCK-058' {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $uiPolicy = Join-Path $repoRoot 'quality/psscriptanalyzer-ui-exceptions.md'

        Test-Path -LiteralPath $uiPolicy -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $uiPolicy -Raw) | Should -Match 'BCK-058'
        (Get-Content -LiteralPath $uiPolicy -Raw) | Should -Match 'PSAvoidUsingWriteHost'
    }

    It 'nao permite avisos novos ou ampliados' {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $toolPath = Join-Path $repoRoot 'tools/Test-PSScriptAnalyzerBaseline.ps1'

        { & $toolPath } | Should -Not -Throw
    }
}
