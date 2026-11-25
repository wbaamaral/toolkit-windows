#requires -version 5.1

# ADR 0007: todo arquivo PowerShell do repositorio deve estar em UTF-8 com BOM.
# Sem BOM, o Windows PowerShell 5.1 le o arquivo como ANSI (CP1252): acentos viram
# mojibake e caracteres como o travessao quebram o parser do script inteiro.

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:sourceFiles = @(
        Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|spec|validation)[\\/]' } |
            ForEach-Object {
                @{
                    Path     = $_.FullName
                    Relative = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
                }
            }
    )
}

Describe 'Codificacao dos arquivos PowerShell (ADR 0007)' {
    It '<Relative> comeca com exatamente um BOM UTF-8' -TestCases $script:sourceFiles {
        param($Path, $Relative)

        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $bytes.Length | Should -BeGreaterOrEqual 3

        $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasBom | Should -BeTrue -Because 'o PS 5.1 le arquivos sem BOM como CP1252'

        $doubleBom = ($bytes.Length -ge 6 -and $bytes[3] -eq 0xEF -and $bytes[4] -eq 0xBB -and $bytes[5] -eq 0xBF)
        $doubleBom | Should -BeFalse -Because 'BOM duplicado impede Import-PowerShellDataFile/Import-Module'
    }

    It '<Relative> e analisado sem erros pelo parser' -TestCases $script:sourceFiles {
        param($Path, $Relative)

        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
