#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot   = Get-XtudoRepoRoot
    $script:moduleRoot = Join-Path $script:repoRoot 'modules/WbaToolkit.Provisioning'
    $script:psd1       = Join-Path $script:moduleRoot 'WbaToolkit.Provisioning.psd1'
    $script:psm1       = Join-Path $script:moduleRoot 'WbaToolkit.Provisioning.psm1'
    $script:publicDir  = Join-Path $script:moduleRoot 'Public'
    $script:scriptPath = Join-Path $script:repoRoot 'provisioning/Inicializar-Windows.ps1'

    $script:expectedPublic = @(
        'Install-ToolkitProvisioning'
        'Uninstall-ToolkitProvisioning'
        'Enable-ToolkitProvisioning'
        'Disable-ToolkitProvisioning'
        'Test-ToolkitProvisioningConfig'
        'Get-ToolkitProvisioningConfig'
        'Get-ToolkitProvisioningState'
        'Reset-ToolkitProvisioningState'
        'Invoke-ToolkitProvisioning'
        'Resume-ToolkitProvisioning'
        'Get-ToolkitProvisioningResult'
    )
    $script:expectedWriteOps = @(
        'Install-ToolkitProvisioning'
        'Uninstall-ToolkitProvisioning'
        'Enable-ToolkitProvisioning'
        'Disable-ToolkitProvisioning'
        'Reset-ToolkitProvisioningState'
        'Invoke-ToolkitProvisioning'
        'Resume-ToolkitProvisioning'
    )

    $script:corePsd1 = Join-Path $script:repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
    Import-Module $script:corePsd1 -Force -ErrorAction Stop
    Import-Module $script:psd1     -Force -ErrorAction Stop

    function New-ProvisioningFixtureConfig {
        param(
            [string]$DeploymentId = 'teste-fixture-001',
            [string]$ComputerName,
            [string]$TimeZoneId = 'UTC',
            [hashtable]$ExtraPolicy = @{}
        )

        $policy = @{
            onError             = 'Stop'
            maxAttemptsPerStep  = 1
            reboot              = 'Never'
            cleanup             = 'RetainAll'
        }
        foreach ($key in $ExtraPolicy.Keys) { $policy[$key] = $ExtraPolicy[$key] }

        [pscustomobject]@{
            schemaVersion = 1
            deploymentId  = $DeploymentId
            computer      = @{ name = $ComputerName; timeZone = $TimeZoneId }
            policy        = $policy
        } | ConvertTo-Json -Depth 10
    }
}

Describe 'WbaToolkit.Provisioning - estrutura do modulo' {
    It 'Possui manifesto, loader e pastas Public/Private/Steps' {
        Test-Path -LiteralPath $script:psd1 | Should -BeTrue
        Test-Path -LiteralPath $script:psm1 | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:moduleRoot 'Public')  | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:moduleRoot 'Private') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:moduleRoot 'Steps')   | Should -BeTrue
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
        foreach ($fn in $script:expectedWriteOps) {
            $file = Join-Path $script:publicDir "$fn.ps1"
            $content = Get-Content -LiteralPath $file -Raw
            $content | Should -Match 'SupportsShouldProcess'
        }
    }

    It 'Script Inicializar-Windows.ps1 existe e parseia' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'Schema JSON v1 existe e e JSON valido' {
        $schemaPath = Join-Path $script:moduleRoot 'Schemas/provisioning-config-v1.schema.json'
        Test-Path -LiteralPath $schemaPath | Should -BeTrue
        { Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Install-ToolkitProvisioning resolve o caminho padrao de Inicializar-Windows.ps1 sem -ScriptPath' {
        # Regressao: a resolucao relativa a $PSScriptRoot ja errou o numero de niveis
        # (achava 'modules/provisioning/...' em vez de '<raiz>/provisioning/...').
        InModuleScope WbaToolkit.Provisioning -Parameters @{ TestDrive = $TestDrive } {
            param($TestDrive)
            if (-not $env:ProgramData) { $env:ProgramData = $TestDrive }
            Mock Initialize-ToolkitProvisioningDirectory { }
            Mock Register-ToolkitProvisioningTask { [pscustomobject]@{ Success = $true; TaskPath = '\WBA\Provisioning\'; TaskName = 'Inicializar-Windows'; Message = 'ok' } }
            { Install-ToolkitProvisioning -Confirm:$false } | Should -Not -Throw
        }
    }
}

Describe 'Test-ToolkitProvisioningSchema' {
    It 'Aceita configuracao minima valida' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeTrue
            $result.Errors.Count | Should -Be 0
        }
    }

    It 'Rejeita configuracao sem schemaVersion' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeFalse
            $result.Errors -join ' ' | Should -Match 'schemaVersion'
        }
    }

    It 'Rejeita schemaVersion nao suportada' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 99; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeFalse
            $result.Errors -join ' ' | Should -Match 'nao e suportada'
        }
    }

    It 'Rejeita campo desconhecido no nivel raiz' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; campoInventado = 1 } | ConvertTo-Json | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeFalse
            $result.Errors -join ' ' | Should -Match 'campoInventado'
        }
    }

    It 'Rejeita campo desconhecido dentro de computer' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; computer = @{ apelido = 'y' } } | ConvertTo-Json | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeFalse
            $result.Errors -join ' ' | Should -Match "computer"
        }
    }

    It 'Rejeita deploymentId com caracteres invalidos' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'id com espaco!' } | ConvertTo-Json | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeFalse
        }
    }

    It 'Rejeita valor invalido em policy.reboot' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; policy = @{ reboot = 'Sempre' } } | ConvertTo-Json | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeFalse
            $result.Errors -join ' ' | Should -Match 'policy.reboot'
        }
    }

    It 'Rejeita senha em texto claro' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'a'; password = 'claro123' }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeFalse
            $result.Errors -join ' ' | Should -Match 'texto claro'
        }
    }

    It 'Aceita senha via secretRef' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'a'; password = @{ secretRef = 'cofre-x' } }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.Errors -join ' ' | Should -Not -Match 'texto claro'
        }
    }

    It 'Emite aviso para secoes de fases futuras' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @() } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $result = Test-ToolkitProvisioningSchema -Config $config
            $result.IsValid | Should -BeTrue
            $result.Warnings -join ' ' | Should -Match "accounts"
        }
    }
}

Describe 'Resolve-ToolkitProvisioningPlan' {
    It 'Produz a ordem determinística das 5 etapas da Fase 1' {
        InModuleScope WbaToolkit.Provisioning {
            $plan = Resolve-ToolkitProvisioningPlan -StepRegistry (Get-ToolkitProvisioningStepRegistry)
            ($plan | ForEach-Object Id) -join ',' | Should -Be 'preflight.system,identity.hostname,computer.locale,network.configure,certificates.install,remoteaccess.winrm,remoteaccess.rdp,firewall.rules,validation.final,cleanup.finalize'
        }
    }

    It 'Detecta ciclo de dependencias' {
        InModuleScope WbaToolkit.Provisioning {
            $registry = @(
                @{ Id = 'a'; DependsOn = @('b') },
                @{ Id = 'b'; DependsOn = @('a') }
            )
            { Resolve-ToolkitProvisioningPlan -StepRegistry $registry } | Should -Throw '*Ciclo*'
        }
    }

    It 'Falha quando dependencia nao esta registrada' {
        InModuleScope WbaToolkit.Provisioning {
            $registry = @(@{ Id = 'a'; DependsOn = @('inexistente') })
            { Resolve-ToolkitProvisioningPlan -StepRegistry $registry } | Should -Throw '*nao esta registrada*'
        }
    }
}

Describe 'Protect-ToolkitProvisioningLogValue' {
    It 'Redige campos sensiveis mantendo os demais' {
        InModuleScope WbaToolkit.Provisioning {
            $input = [pscustomobject]@{ UserName = 'wbaadmin'; Password = 'segredo'; SecretRef = 'cofre-x' }
            $result = Protect-ToolkitProvisioningLogValue -InputObject $input
            $result.UserName | Should -Be 'wbaadmin'
            $result.Password | Should -Be '***REDACTED***'
        }
    }

    It 'Redige SecureString e PSCredential' {
        InModuleScope WbaToolkit.Provisioning {
            $secure = ConvertTo-SecureString 'x' -AsPlainText -Force
            Protect-ToolkitProvisioningLogValue -InputObject $secure | Should -Be '***REDACTED***'
        }
    }

    It 'Percorre arrays e objetos aninhados' {
        InModuleScope WbaToolkit.Provisioning {
            $input = [pscustomobject]@{ Accounts = @([pscustomobject]@{ Name = 'a'; Token = 'abc' }) }
            $result = Protect-ToolkitProvisioningLogValue -InputObject $input
            $result.Accounts[0].Token | Should -Be '***REDACTED***'
            $result.Accounts[0].Name  | Should -Be 'a'
        }
    }
}

Describe 'Estado atomico (Write/Read-ToolkitProvisioningState)' {
    BeforeEach {
        $script:stateDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'Grava e le de volta o mesmo estado' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ StateDir = $script:stateDir } {
            param($StateDir)
            $state = New-ToolkitProvisioningState -DeploymentId 'x' -ConfigHash 'hash1' -SchemaVersion 1 -ModuleVersion '0.1.0'
            Write-ToolkitProvisioningState -StateDirectory $StateDir -State $state
            $read = Read-ToolkitProvisioningState -StateDirectory $StateDir
            $read.Found | Should -BeTrue
            $read.State.DeploymentId | Should -Be 'x'
            $read.CorruptionDetected | Should -BeFalse
        }
    }

    It 'Mantem state.previous.json apos a segunda gravacao' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ StateDir = $script:stateDir } {
            param($StateDir)
            $state1 = New-ToolkitProvisioningState -DeploymentId 'x' -ConfigHash 'hash1' -SchemaVersion 1 -ModuleVersion '0.1.0'
            Write-ToolkitProvisioningState -StateDirectory $StateDir -State $state1
            $state1.GlobalState = 'Running'
            Write-ToolkitProvisioningState -StateDirectory $StateDir -State $state1
            Test-Path -LiteralPath (Join-Path $StateDir 'state.previous.json') | Should -BeTrue
        }
    }

    It 'Recupera de state.previous.json quando state.json esta corrompido' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ StateDir = $script:stateDir } {
            param($StateDir)
            $state = New-ToolkitProvisioningState -DeploymentId 'x' -ConfigHash 'hash1' -SchemaVersion 1 -ModuleVersion '0.1.0'
            Write-ToolkitProvisioningState -StateDirectory $StateDir -State $state
            $state.GlobalState = 'Running'
            Write-ToolkitProvisioningState -StateDirectory $StateDir -State $state

            Set-Content -LiteralPath (Join-Path $StateDir 'state.json') -Value '{ isto nao e json' -Encoding UTF8

            $read = Read-ToolkitProvisioningState -StateDirectory $StateDir
            $read.Found | Should -BeTrue
            $read.RecoveredFromPrevious | Should -BeTrue
            $read.CorruptionDetected | Should -BeTrue
            $read.State.DeploymentId | Should -Be 'x'
        }
    }

    It 'Retorna Found=$false quando nao ha estado' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ StateDir = (Join-Path $TestDrive 'inexistente') } {
            param($StateDir)
            $read = Read-ToolkitProvisioningState -StateDirectory $StateDir
            $read.Found | Should -BeFalse
        }
    }
}

Describe 'Invoke-ToolkitProvisioningStep - ciclo Test/Set/Verify' {
    It 'Compliant nao chama Set' {
        InModuleScope WbaToolkit.Provisioning {
            function Test-Fake { param($Context) [pscustomobject]@{ Status = 'Compliant'; Message = 'ok'; Evidence = $null } }
            function Set-Fake { param($Context) throw 'Set nao deveria ser chamado' }
            $manifest = @{ Id = 'fake.step'; TestFunction = 'Test-Fake'; SetFunction = 'Set-Fake'; VerifyFunction = 'Test-Fake' }
            $result = Invoke-ToolkitProvisioningStep -StepManifest $manifest -Context ([pscustomobject]@{ Config = $null })
            $result.Status | Should -Be 'Compliant'
        }
    }

    It 'Changed chama Set e depois Verify' {
        InModuleScope WbaToolkit.Provisioning {
            $script:setCalled = $false
            function Test-Fake { param($Context) [pscustomobject]@{ Status = 'Changed'; Message = 'diverge'; Evidence = $null } }
            function Set-Fake { param($Context) $script:setCalled = $true; [pscustomobject]@{ RebootRequired = $false; Message = 'aplicado'; Evidence = $null } }
            function Verify-Fake { param($Context) [pscustomobject]@{ Status = 'Compliant'; Message = 'confirmado'; Evidence = $null } }
            $manifest = @{ Id = 'fake.step'; TestFunction = 'Test-Fake'; SetFunction = 'Set-Fake'; VerifyFunction = 'Verify-Fake' }
            $result = Invoke-ToolkitProvisioningStep -StepManifest $manifest -Context ([pscustomobject]@{ Config = $null })
            $script:setCalled | Should -BeTrue
            $result.Status | Should -Be 'Changed'
            $result.Changed | Should -BeTrue
        }
    }

    It 'RebootRequired nao chama Verify' {
        InModuleScope WbaToolkit.Provisioning {
            function Test-Fake { param($Context) [pscustomobject]@{ Status = 'Changed'; Message = 'diverge'; Evidence = $null } }
            function Set-Fake { param($Context) [pscustomobject]@{ RebootRequired = $true; Message = 'reiniciar'; Evidence = $null } }
            function Verify-Fake { param($Context) throw 'Verify nao deveria ser chamado' }
            $manifest = @{ Id = 'fake.step'; TestFunction = 'Test-Fake'; SetFunction = 'Set-Fake'; VerifyFunction = 'Verify-Fake' }
            $result = Invoke-ToolkitProvisioningStep -StepManifest $manifest -Context ([pscustomobject]@{ Config = $null })
            $result.Status | Should -Be 'RebootRequired'
            $result.RebootRequired | Should -BeTrue
        }
    }

    It 'Sanitiza excecao nao tratada' {
        InModuleScope WbaToolkit.Provisioning {
            function Test-Fake { param($Context) throw 'Falha com password=segredo123 embutida' }
            $manifest = @{ Id = 'fake.step'; TestFunction = 'Test-Fake'; SetFunction = 'Test-Fake'; VerifyFunction = 'Test-Fake' }
            $result = Invoke-ToolkitProvisioningStep -StepManifest $manifest -Context ([pscustomobject]@{ Config = $null })
            $result.Status | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'UnhandledException'
        }
    }
}

Describe 'Etapas de dominio - identity.hostname' {
    It 'Skipped quando computer.name nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitHostnameDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Compliant quando o nome ja bate com o computador atual' {
        InModuleScope WbaToolkit.Provisioning {
            $env:COMPUTERNAME = 'PC-TESTE-FIXO'
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x'; computer = @{ name = 'PC-TESTE-FIXO' } } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitHostnameDesiredState -Context $context).Status | Should -Be 'Compliant'
        }
    }

    It 'Changed quando o nome diverge, e Set chama Rename-Computer e pede reboot' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope WbaToolkit.Provisioning {
            $env:COMPUTERNAME = 'PC-ATUAL'
            Mock Rename-Computer { } -Verifiable
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x'; computer = @{ name = 'OUTRO-NOME' } } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitHostnameDesiredState -Context $context).Status | Should -Be 'Changed'
            $setResult = Set-ToolkitHostnameDesiredState -Context $context -Confirm:$false
            $setResult.RebootRequired | Should -BeTrue
            Should -InvokeVerifiable
        }
    }
}

Describe 'Etapas de dominio - computer.locale' {
    It 'Skipped quando computer.timeZone nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitLocaleDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Changed quando o fuso diverge, e Set chama Set-TimeZone' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'UTC' } }
            Mock Set-TimeZone { } -Verifiable
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x'; computer = @{ timeZone = 'SA Western Standard Time' } } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitLocaleDesiredState -Context $context).Status | Should -Be 'Changed'
            $setResult = Set-ToolkitLocaleDesiredState -Context $context -Confirm:$false
            $setResult.RebootRequired | Should -BeFalse
            Should -InvokeVerifiable
        }
    }

    It 'Compliant quando o fuso ja bate' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'UTC' } }
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x'; computer = @{ timeZone = 'UTC' } } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitLocaleDesiredState -Context $context).Status | Should -Be 'Compliant'
        }
    }
}

Describe 'Etapa preflight.system' {
    It 'Compliant quando administrador e sem outros bloqueios' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Test-IsAdministrator { $true }
            (Test-ToolkitPreflightDesiredState -Context ([pscustomobject]@{ Config = $null })).Status | Should -Be 'Compliant'
        }
    }

    It 'Failed quando nao esta em contexto administrativo' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Test-IsAdministrator { $false }
            (Test-ToolkitPreflightDesiredState -Context ([pscustomobject]@{ Config = $null })).Status | Should -Be 'Failed'
        }
    }
}

Describe 'Etapa cleanup.finalize' {
    BeforeEach {
        $script:workDir    = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) 'Work/x'
        $script:secretsDir = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) 'Secrets/x'
        New-Item -Path $script:workDir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:workDir 'provisioning.json') -Value '{}' -Encoding UTF8
    }

    It 'RetainAll e sempre Compliant' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ WorkDir = $script:workDir; SecretsDir = $script:secretsDir } {
            param($WorkDir, $SecretsDir)
            $paths = [pscustomobject]@{ Work = (Split-Path -Parent $WorkDir); Secrets = (Split-Path -Parent $SecretsDir) }
            $context = [pscustomobject]@{
                Config       = (@{ schemaVersion = 1; deploymentId = 'x'; policy = @{ cleanup = 'RetainAll' } } | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
                Paths        = $paths
                DeploymentId = 'x'
            }
            (Test-ToolkitCleanupFinalizeDesiredState -Context $context).Status | Should -Be 'Compliant'
        }
    }

    It 'RemoveSecretsAndConfig remove a copia de configuracao' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ WorkDir = $script:workDir; SecretsDir = $script:secretsDir } {
            param($WorkDir, $SecretsDir)
            $paths = [pscustomobject]@{ Work = (Split-Path -Parent $WorkDir); Secrets = (Split-Path -Parent $SecretsDir) }
            $context = [pscustomobject]@{
                Config       = (@{ schemaVersion = 1; deploymentId = 'x'; policy = @{ cleanup = 'RemoveSecretsAndConfig' } } | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
                Paths        = $paths
                DeploymentId = 'x'
            }
            (Test-ToolkitCleanupFinalizeDesiredState -Context $context).Status | Should -Be 'Changed'
            Set-ToolkitCleanupFinalizeDesiredState -Context $context -Confirm:$false | Out-Null
            Test-Path -LiteralPath (Join-Path $WorkDir 'provisioning.json') | Should -BeFalse
            (Test-ToolkitCleanupFinalizeDesiredState -Context $context).Status | Should -Be 'Compliant'
        }
    }
}

Describe 'Invoke-ToolkitProvisioning - fluxo fim-a-fim mockado' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'Conclui um deployment cuja configuracao ja esta conforme (sem reboot)' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ Root = $script:root; ComputerName = $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'PC-TESTE-CI' }) } {
            param($Root, $ComputerName)

            Mock Test-IsAdministrator { $true }
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'UTC' } }
            if (-not (Get-Command Get-WSManInstance -ErrorAction SilentlyContinue)) { function Get-WSManInstance { } }
            if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) { function Get-NetFirewallRule { } }
            Mock Get-WSManInstance { }
            Mock Get-NetFirewallRule { }
            Mock Get-ItemProperty { [pscustomobject]@{ fDenyTSConnections = 1 } } -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' }
            Mock Get-ToolkitProvisioningPaths {
                [pscustomobject]@{
                    Root       = $Root
                    Inbox      = Join-Path $Root 'Inbox'
                    Work       = Join-Path $Root 'Work'
                    Logs       = Join-Path $Root 'Logs'
                    Results    = Join-Path $Root 'Results'
                    Secrets    = Join-Path $Root 'Secrets'
                    Quarantine = Join-Path $Root 'Quarantine'
                }
            }.GetNewClosure()

            $inboxDir = Join-Path $Root 'Inbox'
            New-Item -Path $inboxDir -ItemType Directory -Force | Out-Null
            $configPath = Join-Path $inboxDir 'provisioning.json'
            @{
                schemaVersion = 1
                deploymentId  = 'fluxo-completo-001'
                computer      = @{ name = $ComputerName; timeZone = 'UTC' }
                policy        = @{ onError = 'Stop'; maxAttemptsPerStep = 1; reboot = 'Never'; cleanup = 'RetainAll' }
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8

            $result = Invoke-ToolkitProvisioning -Confirm:$false

            $result.GlobalState | Should -Be 'Completed'
            $result.Report | Should -Not -BeNullOrEmpty
            $result.Report.Steps.Count | Should -Be 10
            @($result.Report.Steps | Where-Object Status -eq 'Failed').Count | Should -Be 0

            $stateFile = Join-Path $Root 'Work/fluxo-completo-001/state.json'
            Test-Path -LiteralPath $stateFile | Should -BeTrue

            $resultFile = Join-Path $Root 'Results/fluxo-completo-001/result.json'
            Test-Path -LiteralPath $resultFile | Should -BeTrue
        }
    }

    It 'Recusa reexecutar um deployment ja concluido' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ Root = $script:root; ComputerName = $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'PC-TESTE-CI' }) } {
            param($Root, $ComputerName)

            Mock Test-IsAdministrator { $true }
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'UTC' } }
            if (-not (Get-Command Get-WSManInstance -ErrorAction SilentlyContinue)) { function Get-WSManInstance { } }
            if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) { function Get-NetFirewallRule { } }
            Mock Get-WSManInstance { }
            Mock Get-NetFirewallRule { }
            Mock Get-ItemProperty { [pscustomobject]@{ fDenyTSConnections = 1 } } -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' }
            Mock Get-ToolkitProvisioningPaths {
                [pscustomobject]@{
                    Root       = $Root
                    Inbox      = Join-Path $Root 'Inbox'
                    Work       = Join-Path $Root 'Work'
                    Logs       = Join-Path $Root 'Logs'
                    Results    = Join-Path $Root 'Results'
                    Secrets    = Join-Path $Root 'Secrets'
                    Quarantine = Join-Path $Root 'Quarantine'
                }
            }.GetNewClosure()

            $inboxDir = Join-Path $Root 'Inbox'
            New-Item -Path $inboxDir -ItemType Directory -Force | Out-Null
            $configPath = Join-Path $inboxDir 'provisioning.json'
            @{
                schemaVersion = 1
                deploymentId  = 'ja-concluido-001'
                computer      = @{ name = $ComputerName; timeZone = 'UTC' }
                policy        = @{ reboot = 'Never'; cleanup = 'RetainAll' }
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8

            Invoke-ToolkitProvisioning -Confirm:$false | Out-Null
            { Invoke-ToolkitProvisioning -Confirm:$false } | Should -Throw '*ja esta concluido*'
        }
    }

    It 'Configuracao invalida nao cria nenhum artefato em disco' {
        InModuleScope WbaToolkit.Provisioning -Parameters @{ Root = $script:root } {
            param($Root)

            Mock Get-ToolkitProvisioningPaths {
                [pscustomobject]@{
                    Root       = $Root
                    Inbox      = Join-Path $Root 'Inbox'
                    Work       = Join-Path $Root 'Work'
                    Logs       = Join-Path $Root 'Logs'
                    Results    = Join-Path $Root 'Results'
                    Secrets    = Join-Path $Root 'Secrets'
                    Quarantine = Join-Path $Root 'Quarantine'
                }
            }.GetNewClosure()

            $inboxDir = Join-Path $Root 'Inbox'
            New-Item -Path $inboxDir -ItemType Directory -Force | Out-Null
            $configPath = Join-Path $inboxDir 'provisioning.json'
            '{ "deploymentId": "sem-schema-version" }' | Set-Content -LiteralPath $configPath -Encoding UTF8

            { Invoke-ToolkitProvisioning -Confirm:$false } | Should -Throw '*invalida*'
            Test-Path -LiteralPath (Join-Path $Root 'Work') | Should -BeFalse
        }
    }
}
