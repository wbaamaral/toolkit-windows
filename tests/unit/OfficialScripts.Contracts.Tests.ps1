#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot = Get-XtudoRepoRoot
    $script:contracts = @(
        @{ Name = 'analisar-espaco-disco'; Path = 'scripts/analisar-espaco-disco.ps1' }
        @{ Name = 'configurar-acesso-remoto'; Path = 'scripts/configurar-acesso-remoto.ps1' }
        @{ Name = 'configurar-idioma-regional'; Path = 'scripts/configurar-idioma-regional.ps1' }
        @{ Name = 'diagnosticar-disco-100'; Path = 'scripts/diagnosticar-disco-100.ps1' }
        @{ Name = 'diagnosticar-grafico'; Path = 'scripts/diagnosticar-grafico.ps1' }
        @{ Name = 'diagnosticar-memoria'; Path = 'scripts/diagnosticar-memoria.ps1' }
        @{ Name = 'gerenciar-agendamentos'; Path = 'scripts/gerenciar-agendamentos.ps1' }
        @{ Name = 'gerenciar-copia-sombra'; Path = 'scripts/gerenciar-copia-sombra.ps1' }
        @{ Name = 'gerenciar-copias'; Path = 'scripts/gerenciar-copias.ps1' }
        @{ Name = 'gerenciar-drivers'; Path = 'scripts/gerenciar-drivers.ps1' }
        @{ Name = 'gerenciar-inicializacao'; Path = 'scripts/gerenciar-inicializacao.ps1' }
        @{ Name = 'gerenciar-licenciamento'; Path = 'scripts/gerenciar-licenciamento.ps1' }
        @{ Name = 'gerenciar-ssh'; Path = 'scripts/gerenciar-ssh.ps1' }
        @{ Name = 'inventario-hardware-software'; Path = 'scripts/inventario-hardware-software.ps1' }
        @{ Name = 'limpar-windows'; Path = 'scripts/limpar-windows.ps1' }
        @{ Name = 'limpar-winsxs'; Path = 'scripts/limpar-winsxs.ps1' }
        @{ Name = 'preparar-imagem-windows'; Path = 'scripts/preparar-imagem-windows.ps1' }
        @{ Name = 'remover-perfis-inativos'; Path = 'scripts/remover-perfis-inativos.ps1' }
    )
}

Describe 'Contratos dos scripts operacionais sem suite funcional dedicada' {
    It 'Mantem a relacao de dezoito scripts cobertos' {
        $script:contracts.Count | Should -Be 18
    }

    It 'mantem contratos de existencia, sintaxe e sinopse para cada script' {
        foreach ($contract in $script:contracts) {
            $path = Join-Path $script:repoRoot $contract.Path
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue

            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors) | Should -BeNullOrEmpty

            (Get-Content -LiteralPath $path -Raw) | Should -Match '(?s)<#.*?\.SYNOPSIS'
        }
    }

    It 'permite inspecao isolada com Help sem iniciar o fluxo operacional' {
        foreach ($contract in $script:contracts) {
            $path = Join-Path $script:repoRoot $contract.Path
            $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Help 2>&1)

            $LASTEXITCODE | Should -Be 0
            ($output -join "`n") | Should -Match '(?i)uso|sintaxe|parametro|exemplo'
        }
    }

    It 'oferece WhatIf antes das mutacoes de acesso remoto' {
        $path = Join-Path $script:repoRoot 'scripts/configurar-acesso-remoto.ps1'
        $content = Get-Content -LiteralPath $path -Raw

        $content | Should -Match 'CmdletBinding\(SupportsShouldProcess\s*=\s*\$true'
        $content | Should -Match '\$PSCmdlet\.ShouldProcess\('
        $content | Should -Match "ShouldProcess\('RDP, TermService e NLA', 'Habilitar acesso remoto'\)"
        $content | Should -Match "ShouldProcess\('RDP', 'Desabilitar acesso remoto'\)"
    }
}
