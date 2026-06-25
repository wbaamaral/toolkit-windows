#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot   = Get-XtudoRepoRoot
    $script:moduleRoot = Join-Path $script:repoRoot 'modules/WbaToolkit.Identity'
    $script:psd1       = Join-Path $script:moduleRoot 'WbaToolkit.Identity.psd1'
    $script:psm1       = Join-Path $script:moduleRoot 'WbaToolkit.Identity.psm1'
    $script:publicDir  = Join-Path $script:moduleRoot 'Public'
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/gerenciar-login-automatico.ps1'
    $script:launcher   = Get-XtudoLauncherContent

    $script:expectedPublic = @(
        'Get-AutologonStatus'
        'Enable-Autologon'
        'Disable-Autologon'
        'Set-Autologon'
        'Invoke-AutologonManager'
    )
}

Describe 'WbaToolkit.Identity - estrutura do modulo' {
    It 'Possui manifesto, loader e pastas Public/Private' {
        Test-Path -LiteralPath $script:psd1 | Should -BeTrue
        Test-Path -LiteralPath $script:psm1 | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:moduleRoot 'Public')  | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:moduleRoot 'Private') | Should -BeTrue
    }

    It 'Exporta exatamente as funcoes publicas esperadas (psd1)' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:psd1
        foreach ($fn in $script:expectedPublic) {
            $manifest.FunctionsToExport | Should -Contain $fn
        }
        $manifest.FunctionsToExport.Count | Should -Be $script:expectedPublic.Count
    }

    It 'Declara dependencia do WbaToolkit.Core' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:psd1
        ($manifest.RequiredModules | ForEach-Object { $_.ModuleName }) | Should -Contain 'WbaToolkit.Core'
    }

    It 'Cada funcao publica tem arquivo, Comment-Based Help e parseia' {
        foreach ($fn in $script:expectedPublic) {
            $file = Join-Path $script:publicDir "$fn.ps1"
            Test-Path -LiteralPath $file | Should -BeTrue
            $content = Get-Content -LiteralPath $file -Raw
            $content | Should -Match '\.SYNOPSIS'
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    It 'Operacoes de escrita usam SupportsShouldProcess' {
        foreach ($fn in @('Enable-Autologon', 'Disable-Autologon', 'Set-Autologon')) {
            (Get-Content -LiteralPath (Join-Path $script:publicDir "$fn.ps1") -Raw) |
                Should -Match 'SupportsShouldProcess'
        }
    }
}

Describe 'WbaToolkit.Identity - seguranca da senha (ADR 0005)' {
    It 'Nao grava DefaultPassword em texto claro via Set-ItemProperty' {
        $allSources = Get-ChildItem -LiteralPath $script:moduleRoot -Recurse -Filter '*.ps1' |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        foreach ($src in $allSources) {
            $src | Should -Not -Match "Set-ItemProperty[^\r\n]*DefaultPassword"
        }
    }

    It 'Usa segredo LSA para a senha' {
        (Get-Content -LiteralPath (Join-Path $script:publicDir 'Enable-Autologon.ps1') -Raw) |
            Should -Match "Set-LsaSecret"
    }

    It 'O script operador nao aceita senha por parametro de texto' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        $content | Should -Not -Match '\[string\]\$Password'
        $content | Should -Match 'AsSecureString'
    }
}

Describe 'WbaToolkit.Identity - integracao com o launcher' {
    It 'O script operador esta registrado no xtudo' {
        $script:launcher | Should -Match "Path\s+=\s+'scripts/gerenciar-login-automatico\.ps1'"
    }

    It 'O script operador segue o nome verbo-objeto (ADR 0024)' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
        (Split-Path -Leaf $script:scriptPath) | Should -Be 'gerenciar-login-automatico.ps1'
    }
}
