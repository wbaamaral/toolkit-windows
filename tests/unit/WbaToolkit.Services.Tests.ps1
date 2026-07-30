#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot   = Get-XtudoRepoRoot
    $script:moduleRoot = Join-Path $script:repoRoot 'modules/WbaToolkit.Services'
    $script:psd1       = Join-Path $script:moduleRoot 'WbaToolkit.Services.psd1'
    $script:psm1       = Join-Path $script:moduleRoot 'WbaToolkit.Services.psm1'
    $script:publicDir  = Join-Path $script:moduleRoot 'Public'
    $script:privateDir = Join-Path $script:moduleRoot 'Private'
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/gerenciar-servicos.ps1'
    $script:launcher   = Get-XtudoLauncherContent

    $script:expectedPublic = @(
        'Get-WindowsServiceStatus'
        'Get-WindowsServiceDetail'
        'Start-WindowsService'
        'Stop-WindowsService'
        'Restart-WindowsService'
        'Set-WindowsServiceStartup'
        'Set-WindowsServiceAccount'
        'Invoke-ServiceManager'
    )

    $script:expectedPrivate = @(
        'Resolve-WindowsService'
        'Format-ServiceResult'
    )

    $script:corePsd1 = Join-Path $script:repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
    Import-Module $script:corePsd1 -Force -ErrorAction Stop
    Import-Module $script:psd1     -Force -ErrorAction Stop
}

Describe 'WbaToolkit.Services - estrutura do modulo' {
    It 'Possui manifesto, loader e pastas Public/Private' {
        Test-Path -LiteralPath $script:psd1 | Should -BeTrue
        Test-Path -LiteralPath $script:psm1 | Should -BeTrue
        Test-Path -LiteralPath $script:publicDir  | Should -BeTrue
        Test-Path -LiteralPath $script:privateDir | Should -BeTrue
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

    It 'Cada funcao privada tem arquivo e parseia' {
        foreach ($fn in $script:expectedPrivate) {
            $file = Join-Path $script:privateDir "$fn.ps1"
            Test-Path -LiteralPath $file | Should -BeTrue
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }
}

Describe 'WbaToolkit.Services - contratos das funcoes' {
    Context 'Get-WindowsServiceStatus' {
        It 'Retorna objetos com propriedades esperadas' {
            $result = @(Get-WindowsServiceStatus -Name 'W32Time')
            $result.Count | Should -BeGreaterThan 0
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'DisplayName'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'StartType'
        }

        It 'Suporta filtro por Status' {
            $result = @(Get-WindowsServiceStatus -Status Running -Name 'W32Time')
            foreach ($s in $result) {
                $s.Status | Should -Be 'Running'
            }
        }
    }

    Context 'Get-WindowsServiceDetail' {
        It 'Retorna Success=$true para servico existente' {
            $result = Get-WindowsServiceDetail -Name 'W32Time'
            $result.Success | Should -BeTrue
            $result.Name | Should -Be 'W32Time'
        }

        It 'Retorna Success=$false para servico inexistente' {
            $result = Get-WindowsServiceDetail -Name 'ServicoInexistenteXYZ123'
            $result.Success | Should -BeFalse
        }
    }

    Context 'Invoke-ServiceManager' {
        It 'Diagnostico retorna contadores' {
            $result = Invoke-ServiceManager -Acao Diagnostico
            $result.Success | Should -BeTrue
            $result.RunningCount | Should -BeGreaterThan 0
        }

        It 'Listar retorna array de servicos' {
            $result = @(Invoke-ServiceManager -Acao Listar)
            $result.Count | Should -BeGreaterThan 10
        }
    }
}

Describe 'WbaToolkit.Services - integracao com o launcher' {
    It 'O script operador esta registrado no xtudo' {
        $script:launcher | Should -Match "Path\s+=\s+'scripts/gerenciar-servicos\.ps1'"
    }

    It 'O script operador segue o nome verbo-objeto' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
        (Split-Path -Leaf $script:scriptPath) | Should -Be 'gerenciar-servicos.ps1'
    }
}
