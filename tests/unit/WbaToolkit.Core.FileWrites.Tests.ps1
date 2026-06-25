#requires -version 5.1

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Force
}

Describe 'Xtudo escrita de arquivos do core' {
    It 'Cria diretórios pai ao gravar texto UTF-8' {
        $target = Join-Path $TestDrive 'nested\reports\saida.txt'

        Write-TextFileUtf8 -Path $target -Content 'abc'

        Test-Path -LiteralPath $target | Should -BeTrue
        Get-Content -LiteralPath $target -Raw | Should -Match 'abc'
    }

    It 'Cria diretórios pai ao registrar log estruturado' {
        $target = Join-Path $TestDrive 'nested\logs\saida.log'

        Write-ScriptLog -Message 'linha de teste' -Level INFO -LogPath $target

        Test-Path -LiteralPath $target | Should -BeTrue
        Get-Content -LiteralPath $target -Raw | Should -Match 'linha de teste'
    }
}
