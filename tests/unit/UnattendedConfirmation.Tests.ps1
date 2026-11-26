#requires -version 5.1

# BCK-065: confirmacoes aninhadas (ConfirmImpact High) nao podem travar execucao
# desassistida nem contar acao recusada como sucesso.

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    function script:Get-ScriptAst([string]$RelativePath) {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:repoRoot $RelativePath), [ref]$tokens, [ref]$errors)
    }

    function script:Get-CommandCall($Ast, [string]$Name) {
        @($Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Name
        }, $true))
    }
}

Describe 'Chamadas apos confirmacao explicita passam -Confirm:$false' {
    It 'remover-perfis-inativos -Silent chama Remove-Profiles com -Confirm:$false' {
        $ast = Get-ScriptAst 'scripts/remover-perfis-inativos.ps1'
        $calls = Get-CommandCall $ast 'Remove-Profiles'
        $calls.Count | Should -BeGreaterOrEqual 2
        foreach ($call in $calls) { $call.Extent.Text | Should -Match '-Confirm:\$false' }
    }

    It 'limpar-winsxs chama Invoke-ComponentStoreCleanup com -Confirm:$false apos Read-YesNo' {
        $ast = Get-ScriptAst 'scripts/limpar-winsxs.ps1'
        $calls = Get-CommandCall $ast 'Invoke-ComponentStoreCleanup'
        $calls.Count | Should -BeGreaterOrEqual 1
        foreach ($call in $calls) { $call.Extent.Text | Should -Match '-Confirm:\$false' }
    }
}

Describe 'Remove-Profiles (remover-perfis-inativos.ps1)' {
    BeforeAll {
        $ast = Get-ScriptAst 'scripts/remover-perfis-inativos.ps1'
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Remove-Profiles' }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
        function script:Write-Ok { param($Message) }
        function script:Write-Fail { param($Message) }
        function script:Write-ProfileLog { param($Message, $Level) }
        $script:DryRun = $false
    }

    It 'Perfil nao removido por -WhatIf nao conta como sucesso' {
        Mock Get-CimInstance { throw 'Nao deveria consultar o perfil.' }
        $list = New-Object 'System.Collections.Generic.List[PSCustomObject]'
        $list.Add([pscustomobject]@{ UserName = 'u1'; SizeDisplay = '1 MB'; SizeBytes = 1MB; LocalPath = 'C:\Users\u1'; SID = 'S-1-5-21-1' })

        $r = Remove-Profiles -ToDelete $list -WhatIf 6> $null

        $r.Results[0].Success | Should -BeFalse
        $r.FreedBytes | Should -Be 0
    }
}
