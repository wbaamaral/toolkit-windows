#requires -version 5.1

# BCK-065: scripts operacionais devolvem codigo de saida diferente de 0 em falha.

BeforeDiscovery {
    $script:gerenciar = @('gerenciar-copias', 'gerenciar-copia-sombra', 'gerenciar-agendamentos')
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    function script:Get-ScriptAst([string]$Name) {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:repoRoot "scripts/$Name.ps1"), [ref]$tokens, [ref]$errors)
    }
}

Describe 'Codigo de saida dos scripts gerenciar-*' {
    It '<_> sai com $script:exitCode dentro do finally do bloco principal' -ForEach $script:gerenciar {
        $ast = Get-ScriptAst $_
        $mainTry = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] -and $_.Finally }) | Select-Object -Last 1
        $mainTry | Should -Not -BeNullOrEmpty
        $mainTry.Finally.Extent.Text | Should -Match 'exit \$script:exitCode'
    }

    It '<_> marca exitCode = 1 em toda falha operacional do bloco principal' -ForEach $script:gerenciar {
        $ast = Get-ScriptAst $_
        $mainTry = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] -and $_.Finally }) | Select-Object -Last 1
        $falhas = @($mainTry.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Write-Fail' -and $n.Extent.Text -notmatch 'LastResult'
        }, $true))
        $falhas.Count | Should -BeGreaterThan 0
        $text = $mainTry.Extent.Text -split "`r?`n"
        foreach ($falha in $falhas) {
            $linha = $falha.Extent.StartLineNumber - $mainTry.Extent.StartLineNumber
            $text[$linha] | Should -Match '\$script:exitCode = 1'
        }
    }
}

Describe 'Codigo de saida de testar-conectividade-internet.ps1' {
    It 'Sai com 1 quando o resultado geral e FALHA ou BLOQUEADO' {
        $ast = Get-ScriptAst 'testar-conectividade-internet'
        $ast.Extent.Text | Should -Match "if \(\`$report\.Blocked -or \`$overall -eq 'FALHA'\) \{ exit 1 \}"
    }
}
