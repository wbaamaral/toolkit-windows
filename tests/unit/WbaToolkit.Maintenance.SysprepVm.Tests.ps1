#requires -version 5.1

if ($env:OS -ne 'Windows_NT') {
    Describe 'WbaToolkit.Maintenance - sysprep em VM - requisito de plataforma' {
        It 'Ignorado fora do Windows: requer Registro, CIM e AppX' -Skip { }
    }
    return
}

Describe 'WbaToolkit.Maintenance - sysprep para generalizar VM (BCK-072)' {

    BeforeAll {
        $toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $toolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1')               -Force -ErrorAction Stop
        Import-Module (Join-Path $toolkitRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1') -Force -ErrorAction Stop
        $script:scriptPath = Join-Path $toolkitRoot 'scripts/preparar-imagem-windows.ps1'
    }

    Context 'Get-SysprepSystemStateIssue' {
        BeforeEach {
            # Estado limpo: nada de chave de upgrade/reinicio, sem BitLocker e SysprepStatus normal.
            Mock -CommandName 'Test-Path' -ModuleName 'WbaToolkit.Maintenance' -MockWith { $false }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ DriveLetter = 'C:'; ConversionStatus = 0; ProtectionStatus = 0 }
            }
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ GeneralizationState = 7 }
            } -ParameterFilter { $LiteralPath -like '*SysprepStatus' }
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ BootExecute = 'autocheck autochk *' }
            } -ParameterFilter { $LiteralPath -like '*Session Manager' }
        }

        It 'Sistema limpo nao gera condicao' {
            InModuleScope WbaToolkit.Maintenance {
                @(Get-SysprepSystemStateIssue).Count | Should -Be 0
            }
        }

        It 'BitLocker ligado no volume do sistema e erro' {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ DriveLetter = 'C:'; ConversionStatus = 1; ProtectionStatus = 1 }
            }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r.Count       | Should -Be 1
                $r[0].Check    | Should -Be 'BitLocker'
                $r[0].Severity | Should -Be 'Error'
                $r[0].Message  | Should -Match 'manage-bde -off'
            }
        }

        It 'Criptografia de dispositivo aguardando ativacao (criptografado, protecao desligada) tambem e erro' {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ DriveLetter = 'C:'; ConversionStatus = 1; ProtectionStatus = 0 }
            }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r[0].Check    | Should -Be 'BitLocker'
                $r[0].Severity | Should -Be 'Error'
            }
        }

        It 'Consulta o volume do SystemDrive no namespace do BitLocker' {
            InModuleScope WbaToolkit.Maintenance {
                $null = Get-SysprepSystemStateIssue
                Should -Invoke -CommandName 'Get-CimInstance' -Times 1 -Exactly -ParameterFilter {
                    $Namespace -eq 'root/cimv2/Security/MicrosoftVolumeEncryption' -and
                    $ClassName -eq 'Win32_EncryptableVolume' -and
                    $Filter -eq "DriveLetter='$env:SystemDrive'"
                }
            }
        }

        It 'Falha ao consultar o BitLocker vira aviso, nao erro' {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'WbaToolkit.Maintenance' -MockWith { throw 'Acesso negado' }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r[0].Check    | Should -Be 'BitLocker'
                $r[0].Severity | Should -Be 'Warning'
                $r[0].Message  | Should -Match 'manage-bde -status'
            }
        }

        It 'Instalacao atualizada (chave Setup\Upgrade) e erro' {
            Mock -CommandName 'Test-Path' -ModuleName 'WbaToolkit.Maintenance' -MockWith { $true } `
                -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\Setup\Upgrade' }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r.Count       | Should -Be 1
                $r[0].Check    | Should -Be 'Upgrade'
                $r[0].Severity | Should -Be 'Error'
            }
        }

        It 'Reinicio pendente do servicing (CBS) e erro' {
            Mock -CommandName 'Test-Path' -ModuleName 'WbaToolkit.Maintenance' -MockWith { $true } `
                -ParameterFilter { $LiteralPath -like '*Component Based Servicing\RebootPending' }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r.Count       | Should -Be 1
                $r[0].Check    | Should -Be 'RebootPending'
                $r[0].Severity | Should -Be 'Error'
                $r[0].Message  | Should -Match 'CBS'
            }
        }

        It 'Reinicio exigido pelo Windows Update e erro' {
            Mock -CommandName 'Test-Path' -ModuleName 'WbaToolkit.Maintenance' -MockWith { $true } `
                -ParameterFilter { $LiteralPath -like '*WindowsUpdate\Auto Update\RebootRequired' }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r[0].Check    | Should -Be 'RebootPending'
                $r[0].Severity | Should -Be 'Error'
                $r[0].Message  | Should -Match 'Windows Update'
            }
        }

        It 'Renomeacoes de arquivo pendentes sao apenas aviso' {
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ PendingFileRenameOperations = @('\??\C:\temp\a.dll', '') }
            } -ParameterFilter { $LiteralPath -like '*Session Manager' }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r.Count       | Should -Be 1
                $r[0].Severity | Should -Be 'Warning'
                $r[0].Message  | Should -Match 'PendingFileRenameOperations'
            }
        }

        It 'GeneralizationState diferente de 7 e aviso de estado incompleto' {
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ GeneralizationState = 4 }
            } -ParameterFilter { $LiteralPath -like '*SysprepStatus' }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepSystemStateIssue)
                $r.Count       | Should -Be 1
                $r[0].Check    | Should -Be 'SysprepStatus'
                $r[0].Severity | Should -Be 'Warning'
            }
        }
    }

    Context 'Test-SysprepEnvironment com estado do sistema' {
        BeforeEach {
            Mock -CommandName 'Get-SysprepAppxProvisioningIssue' -ModuleName 'WbaToolkit.Maintenance' -MockWith { @() }
            Mock -CommandName 'Get-SysprepGroupPolicyEvidence' -ModuleName 'WbaToolkit.Maintenance' -MockWith { }
        }

        It 'Erro de estado do sistema invalida no modo Block (padrao)' {
            Mock -CommandName 'Get-SysprepSystemStateIssue' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ Check = 'BitLocker'; Severity = 'Error'; Message = 'BitLocker ativo no volume C:' }
            }
            $r = Test-SysprepEnvironment
            $r.IsValid                  | Should -BeFalse
            $r.Errors                   | Should -Contain 'BitLocker ativo no volume C:'
            $r.SystemStateIssues.Count  | Should -Be 1
        }

        It 'Com SystemStatePolicy Warn o erro vira aviso' {
            Mock -CommandName 'Get-SysprepSystemStateIssue' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ Check = 'BitLocker'; Severity = 'Error'; Message = 'BitLocker ativo no volume C:' }
            }
            $r = Test-SysprepEnvironment -SystemStatePolicy Warn
            $r.Errors   | Should -Not -Contain 'BitLocker ativo no volume C:'
            $r.Warnings | Should -Contain 'BitLocker ativo no volume C:'
        }

        It 'Aviso de estado do sistema nunca invalida' {
            Mock -CommandName 'Get-SysprepSystemStateIssue' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ Check = 'SysprepStatus'; Severity = 'Warning'; Message = 'Estado incompleto' }
            }
            $r = Test-SysprepEnvironment
            $r.Errors   | Should -Not -Contain 'Estado incompleto'
            $r.Warnings | Should -Contain 'Estado incompleto'
        }

        It 'Generalizacao anterior nao bloqueia mais (clone de template pode ser generalizado de novo)' {
            Mock -CommandName 'Get-SysprepSystemStateIssue' -ModuleName 'WbaToolkit.Maintenance' -MockWith { }
            $r = Test-SysprepEnvironment
            ($r.Errors -join ' ') | Should -Not -Match 'ja passou por sysprep'
            $r.SystemStateIssues.Count | Should -Be 0
        }
    }

    Context 'Get-SysprepAppxProvisioningIssue - app da imagem atualizado pela Store' {
        BeforeEach {
            Mock -CommandName 'Get-Service' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ Status = 'Running'; StartType = 'Manual' }
            } -ParameterFilter { $Name -eq 'AppXSvc' }
            Mock -CommandName 'Get-AppxProvisionedPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ DisplayName = 'Microsoft.WindowsCalculator'; Version = '10.1906.55.0' }
            }
        }

        It 'Versao mais nova que a provisionada, instalada para usuario real, e bloqueador' {
            Mock -CommandName 'Get-AppxPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{
                    Name                   = 'Microsoft.WindowsCalculator'
                    PackageFullName        = 'Microsoft.WindowsCalculator_11.2405.2.0_x64__8wekyb3d8bbwe'
                    Version                = '11.2405.2.0'
                    Architecture           = 'X64'
                    Publisher              = 'CN=Microsoft'
                    PackageUserInformation = @([pscustomobject]@{ UserSecurityId = 'S-1-5-21-1-2-3-1001'; PackageUserInstallState = 'Installed' })
                }
            }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepAppxProvisioningIssue)
                $r.Count              | Should -Be 1
                $r[0].Severity        | Should -Be 'Blocker'
                $r[0].Reason          | Should -Be 'UpdatedForUserButProvisionedOlder'
                $r[0].PackageFullName | Should -Be 'Microsoft.WindowsCalculator_11.2405.2.0_x64__8wekyb3d8bbwe'
            }
        }

        It 'Mesma versao da provisionada nao e bloqueador' {
            Mock -CommandName 'Get-AppxPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{
                    Name                   = 'Microsoft.WindowsCalculator'
                    PackageFullName        = 'Microsoft.WindowsCalculator_10.1906.55.0_x64__8wekyb3d8bbwe'
                    Version                = '10.1906.55.0'
                    Architecture           = 'X64'
                    Publisher              = 'CN=Microsoft'
                    PackageUserInformation = @([pscustomobject]@{ UserSecurityId = 'S-1-5-21-1-2-3-1001'; PackageUserInstallState = 'Installed' })
                }
            }
            InModuleScope WbaToolkit.Maintenance {
                @(Get-SysprepAppxProvisioningIssue -IncludeWarnings).Count | Should -Be 0
            }
        }

        It 'Com versao antiga e nova instaladas, so a nova e apontada' {
            Mock -CommandName 'Get-AppxPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{
                    Name                   = 'Microsoft.WindowsCalculator'
                    PackageFullName        = 'Microsoft.WindowsCalculator_10.1906.55.0_x64__8wekyb3d8bbwe'
                    Version                = '10.1906.55.0'
                    Architecture           = 'X64'
                    Publisher              = 'CN=Microsoft'
                    PackageUserInformation = @([pscustomobject]@{ UserSecurityId = 'S-1-5-21-1-2-3-1002'; PackageUserInstallState = 'Installed' })
                }
                [pscustomobject]@{
                    Name                   = 'Microsoft.WindowsCalculator'
                    PackageFullName        = 'Microsoft.WindowsCalculator_11.2405.2.0_x64__8wekyb3d8bbwe'
                    Version                = '11.2405.2.0'
                    Architecture           = 'X64'
                    Publisher              = 'CN=Microsoft'
                    PackageUserInformation = @([pscustomobject]@{ UserSecurityId = 'S-1-5-21-1-2-3-1001'; PackageUserInstallState = 'Installed' })
                }
            }
            InModuleScope WbaToolkit.Maintenance {
                $r = @(Get-SysprepAppxProvisioningIssue)
                $r.Count              | Should -Be 1
                $r[0].PackageFullName | Should -Match '11\.2405'
                $r[0].Users           | Should -Be @('S-1-5-21-1-2-3-1001')
            }
        }

        It 'Framework atualizado continua so como aviso' {
            Mock -CommandName 'Get-AppxProvisionedPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ DisplayName = 'Microsoft.VCLibs.140.00'; Version = '14.0.30035.0' }
            }
            Mock -CommandName 'Get-AppxPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{
                    Name                   = 'Microsoft.VCLibs.140.00'
                    PackageFullName        = 'Microsoft.VCLibs.140.00_14.0.33519.0_x64__8wekyb3d8bbwe'
                    Version                = '14.0.33519.0'
                    Architecture           = 'X64'
                    Publisher              = 'CN=Microsoft'
                    IsFramework            = $true
                    PackageUserInformation = @([pscustomobject]@{ UserSecurityId = 'S-1-5-21-1-2-3-1001'; PackageUserInstallState = 'Installed' })
                }
            }
            InModuleScope WbaToolkit.Maintenance {
                @(Get-SysprepAppxProvisioningIssue).Count | Should -Be 0
                $r = @(Get-SysprepAppxProvisioningIssue -IncludeWarnings)
                $r[0].Severity | Should -Be 'Warning'
            }
        }

        It 'Versao provisionada ilegivel nao gera bloqueador falso' {
            Mock -CommandName 'Get-AppxProvisionedPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ DisplayName = 'Microsoft.WindowsCalculator' }
            }
            Mock -CommandName 'Get-AppxPackage' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{
                    Name                   = 'Microsoft.WindowsCalculator'
                    PackageFullName        = 'Microsoft.WindowsCalculator_11.2405.2.0_x64__8wekyb3d8bbwe'
                    Version                = '11.2405.2.0'
                    Architecture           = 'X64'
                    Publisher              = 'CN=Microsoft'
                    PackageUserInformation = @([pscustomobject]@{ UserSecurityId = 'S-1-5-21-1-2-3-1001'; PackageUserInstallState = 'Installed' })
                }
            }
            InModuleScope WbaToolkit.Maintenance {
                @(Get-SysprepAppxProvisioningIssue -IncludeWarnings).Count | Should -Be 0
            }
        }
    }

    Context 'Invoke-SysprepGeneralize' {
        It 'Executa com /quiet, aguarda e devolve o codigo de saida' {
            Mock -CommandName 'Start-Process' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ ExitCode = 31 }
            }
            InModuleScope WbaToolkit.Maintenance {
                Invoke-SysprepGeneralize -SysprepPath 'C:\fake\sysprep.exe' -Confirm:$false | Should -Be 31
                Should -Invoke -CommandName 'Start-Process' -Times 1 -Exactly -ParameterFilter {
                    $FilePath -eq 'C:\fake\sysprep.exe' -and
                    $ArgumentList -eq '/oobe /generalize /shutdown /quiet' -and
                    $Wait -and $PassThru
                }
            }
        }

        It 'Com -WhatIf nao executa o sysprep' {
            Mock -CommandName 'Start-Process' -ModuleName 'WbaToolkit.Maintenance' -MockWith { throw 'nao deveria executar' }
            InModuleScope WbaToolkit.Maintenance {
                Invoke-SysprepGeneralize -SysprepPath 'C:\fake\sysprep.exe' -WhatIf | Should -Be 0
                Should -Invoke -CommandName 'Start-Process' -Times 0 -Exactly
            }
        }
    }

    Context 'Move-SysprepSessionArtifact' {
        BeforeEach {
            $raiz = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $sessaoPath = Join-Path $raiz 'Relatorios\preparar-imagem\20261128_100000'
            $logs    = Join-Path $sessaoPath 'logs'
            $backups = Join-Path $sessaoPath 'backups'
            New-Item -ItemType Directory -Path $logs, $backups -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $logs 'preparar-imagem.log') -Value 'log'
            Set-Content -LiteralPath (Join-Path $sessaoPath 'relatorio-preparacao-imagem.json') -Value '{}'
            Set-Content -LiteralPath (Join-Path $backups 'NTUSER.DAT.bak') -Value 'hive'
            Set-Content -LiteralPath (Join-Path $backups 'politicas-microsoft.reg') -Value 'reg'
            $script:sessao = [pscustomobject]@{
                StartedAt   = Get-Date
                Mode        = 'Preparacao'
                ReportsRoot = Join-Path $raiz 'Relatorios'
                Path        = $sessaoPath
                LogsPath    = $logs
                BackupsPath = $backups
            }
            $script:destinoRaiz = Join-Path $raiz 'compartilhamento'
        }

        It 'Sem copia: remove so os backups e mantem relatorio e log' {
            $sessao = $script:sessao
            $r = InModuleScope WbaToolkit.Maintenance -Parameters @{ S = $sessao } {
                param($S) Move-SysprepSessionArtifact -Session $S -Confirm:$false
            }
            Test-Path -LiteralPath $sessao.BackupsPath | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $sessao.LogsPath 'preparar-imagem.log') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $sessao.Path 'relatorio-preparacao-imagem.json') | Should -BeTrue
            $r.CopiedTo        | Should -BeNullOrEmpty
            $r.RemovedPaths    | Should -Be @($sessao.BackupsPath)
            $r.Session.Path    | Should -Be $sessao.Path
        }

        It 'Com -KeepInImage nao remove nada' {
            $sessao = $script:sessao
            $r = InModuleScope WbaToolkit.Maintenance -Parameters @{ S = $sessao } {
                param($S) Move-SysprepSessionArtifact -Session $S -KeepInImage -Confirm:$false
            }
            Test-Path -LiteralPath (Join-Path $sessao.BackupsPath 'NTUSER.DAT.bak') | Should -BeTrue
            @($r.RemovedPaths).Count | Should -Be 0
        }

        It 'Com copia: copia tudo para fora, remove a sessao local e redireciona os caminhos' {
            $sessao = $script:sessao
            $destinoRaiz = $script:destinoRaiz
            $r = InModuleScope WbaToolkit.Maintenance -Parameters @{ S = $sessao; D = $destinoRaiz } {
                param($S, $D) Move-SysprepSessionArtifact -Session $S -CopyTo $D -Confirm:$false
            }
            $esperado = Join-Path $destinoRaiz "$($env:COMPUTERNAME)_20261128_100000"
            $r.CopiedTo | Should -Be $esperado
            Test-Path -LiteralPath (Join-Path $esperado 'backups\NTUSER.DAT.bak')    | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $esperado 'logs\preparar-imagem.log')  | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $esperado 'relatorio-preparacao-imagem.json') | Should -BeTrue
            Test-Path -LiteralPath $sessao.Path | Should -BeFalse
            $r.Session.Path        | Should -Be $esperado
            $r.Session.LogsPath    | Should -Be (Join-Path $esperado 'logs')
            $r.Session.BackupsPath | Should -Be (Join-Path $esperado 'backups')
            $r.Session.ReportsRoot | Should -Be $sessao.ReportsRoot
        }

        It 'Com copia e -KeepInImage: copia e mantem a sessao local' {
            $sessao = $script:sessao
            $destinoRaiz = $script:destinoRaiz
            $r = InModuleScope WbaToolkit.Maintenance -Parameters @{ S = $sessao; D = $destinoRaiz } {
                param($S, $D) Move-SysprepSessionArtifact -Session $S -CopyTo $D -KeepInImage -Confirm:$false
            }
            $r.CopiedTo | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $sessao.BackupsPath 'NTUSER.DAT.bak') | Should -BeTrue
            $r.Session.Path | Should -Be $sessao.Path
        }

        It 'Falha na copia lanca excecao antes de remover qualquer coisa' {
            $sessao = $script:sessao
            $destinoRaiz = $script:destinoRaiz
            Mock -CommandName 'Copy-Item' -ModuleName 'WbaToolkit.Maintenance' -MockWith { throw 'destino inacessivel' }
            {
                InModuleScope WbaToolkit.Maintenance -Parameters @{ S = $sessao; D = $destinoRaiz } {
                    param($S, $D) Move-SysprepSessionArtifact -Session $S -CopyTo $D -Confirm:$false
                }
            } | Should -Throw '*destino inacessivel*'
            Test-Path -LiteralPath (Join-Path $sessao.BackupsPath 'NTUSER.DAT.bak') | Should -BeTrue
            Test-Path -LiteralPath $sessao.Path | Should -BeTrue
        }
    }

    Context 'preparar-imagem-windows.ps1 - ordem antes do sysprep' {
        BeforeAll {
            $script:conteudo = [System.IO.File]::ReadAllText($script:scriptPath)
            $tokens = $null; $erros = $null
            $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:scriptPath, [ref]$tokens, [ref]$erros)
            $script:errosParse = $erros
        }

        It 'Script sem erro de sintaxe' {
            @($script:errosParse).Count | Should -Be 0
        }

        It 'Expoe -CopiarRelatorioPara e -ManterArtefatosNaImagem' {
            $nomes = @($script:ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $nomes | Should -Contain 'CopiarRelatorioPara'
            $nomes | Should -Contain 'ManterArtefatosNaImagem'
        }

        It 'Grava o relatorio e tira os artefatos da imagem antes de chamar o sysprep' {
            $iRelatorio = $script:conteudo.IndexOf('Relatorio gravado antes do sysprep')
            $iArtefatos = $script:conteudo.IndexOf('Move-SysprepSessionArtifact')
            $iSysprep   = $script:conteudo.IndexOf('Invoke-SysprepGeneralize -SysprepPath')
            $iRelatorio | Should -BeGreaterThan 0
            $iArtefatos | Should -BeGreaterThan $iRelatorio
            $iSysprep   | Should -BeGreaterThan $iArtefatos
        }

        It 'Nao chama mais o sysprep.exe direto sem /quiet' {
            $script:conteudo | Should -Not -Match "-ArgumentList '/oobe /generalize /shutdown'"
        }

        It 'Com -SemSysprep o estado do sistema vira aviso' {
            $script:conteudo | Should -Match "if \(\`$SemSysprep\) \{ 'Warn' \} else \{ 'Block' \}"
            $script:conteudo | Should -Match '-SystemStatePolicy \$politicaEstadoSistema'
        }
    }
}
