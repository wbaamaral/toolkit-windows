#requires -version 5.1

$ToolkitRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CorePath     = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$ModulePath   = Join-Path $ToolkitRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1'

Import-Module $CorePath    -Force -ErrorAction Stop
Import-Module $ModulePath  -Force -ErrorAction Stop

Describe 'WbaToolkit.Maintenance' {

    Context 'Exportacao do modulo' {
        It 'Deve exportar Get-DefaultUserHivePath' {
            (Get-Command Get-DefaultUserHivePath -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Invoke-WithDefaultUserHive' {
            (Get-Command Invoke-WithDefaultUserHive -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Import-RegistryTweakToDefaultProfile' {
            (Get-Command Import-RegistryTweakToDefaultProfile -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Test-SysprepEnvironment' {
            (Get-Command Test-SysprepEnvironment -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Invoke-SysprepPreparation' {
            (Get-Command Invoke-SysprepPreparation -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Nao deve exportar funcoes privadas' {
            Get-Command Backup-DefaultUserHive               -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Invoke-RegFileImport                 -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Read-RegFileContent                  -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Get-SysprepAppxProvisioningIssue     -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Import-RegistryTweakToDefaultProfile - DryRun' {
        It 'Deve retornar resultado DryRun sem modificar o registro' {
            $tempReg = [System.IO.Path]::GetTempFileName() + '.reg'
            try {
                Set-Content -Path $tempReg -Value "Windows Registry Editor Version 5.00`r`n`r`n[hkey_users\default\Software\WBA\Test]`r`n" -Encoding ASCII
                $resultado = Import-RegistryTweakToDefaultProfile -RegFilePath $tempReg -DryRun
                $resultado.Success | Should -BeTrue
                $resultado.Message | Should -Be 'DryRun.'
                $resultado.Tweak   | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $tempReg -Force -ErrorAction SilentlyContinue
            }
        }
        It 'Deve usar o nome do arquivo (sem extensao) como nome do tweak' {
            $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "wba_mnt_$([System.Guid]::NewGuid().ToString('N'))")
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            try {
                $regPath = Join-Path $tempDir 'Meu_Tweak_Teste.reg'
                Set-Content -Path $regPath -Value "Windows Registry Editor Version 5.00`r`n" -Encoding ASCII
                $resultado = Import-RegistryTweakToDefaultProfile -RegFilePath $regPath -DryRun
                $resultado.Tweak | Should -Be 'Meu_Tweak_Teste'
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Test-SysprepEnvironment' {
        It 'Deve retornar objeto com todas as propriedades esperadas' {
            $resultado = Test-SysprepEnvironment
            $resultado                             | Should -Not -BeNullOrEmpty
            $resultado.PSObject.Properties.Name   | Should -Contain 'IsValid'
            $resultado.PSObject.Properties.Name   | Should -Contain 'OsVersion'
            $resultado.PSObject.Properties.Name   | Should -Contain 'BuildNumber'
            $resultado.PSObject.Properties.Name   | Should -Contain 'Errors'
            $resultado.PSObject.Properties.Name   | Should -Contain 'Warnings'
        }
        It 'Deve retornar IsValid false quando nao e Administrador' {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltinRole]::Administrator
            )
            if (-not $isAdmin) {
                $resultado = Test-SysprepEnvironment
                $resultado.IsValid | Should -BeFalse
                $resultado.Errors  | Should -Contain 'Este script requer execucao como Administrador.'
            }
            else {
                Set-ItResult -Skipped -Because 'Sessao elevada - cenario sem admin nao e testavel'
            }
        }
        It 'Errors deve ser um array' {
            $resultado = Test-SysprepEnvironment
            $resultado.Errors.GetType().IsArray | Should -BeTrue
        }
        It 'Warnings deve ser um array' {
            $resultado = Test-SysprepEnvironment
            $resultado.Warnings.GetType().IsArray | Should -BeTrue
        }
    }

    Context 'Exportacao — funcoes v1.2.0' {
        It 'Deve exportar Remove-SafePath' {
            (Get-Command Remove-SafePath -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Get-DiskInfo' {
            (Get-Command Get-DiskInfo -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Get-FilesystemErrorEvent' {
            (Get-Command Get-FilesystemErrorEvent -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Write-MaintenanceEvent' {
            (Get-Command Write-MaintenanceEvent -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Invoke-FilesystemCheck' {
            (Get-Command Invoke-FilesystemCheck -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Invoke-EventLogMaintenance' {
            (Get-Command Invoke-EventLogMaintenance -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Get-ComponentStoreInfo' {
            (Get-Command Get-ComponentStoreInfo -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Invoke-ComponentStoreCleanup' {
            (Get-Command Invoke-ComponentStoreCleanup -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Nao deve exportar Register-MaintenanceEventSource' {
            Get-Command Register-MaintenanceEventSource -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        It 'Nao deve exportar ConvertTo-StoreSizeGB' {
            Get-Command ConvertTo-StoreSizeGB -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Remove-SafePath' {
        It 'Nao deve lancar excecao para caminho inexistente' {
            { Remove-SafePath -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'wba_naoexiste_xyz')) } |
                Should -Not -Throw
        }
        It 'Deve remover arquivos do diretorio' {
            $tempDir = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(),
                "wba_rsp_$([System.Guid]::NewGuid().ToString('N'))"
            )
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            try {
                Set-Content -Path (Join-Path $tempDir 'arquivo.txt') -Value 'conteudo'
                Remove-SafePath -Path $tempDir -AllowedRoot $tempDir
                (Get-ChildItem $tempDir -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        It 'Deve RECUSAR remocao fora das raizes permitidas (preserva o conteudo)' {
            $tempDir = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(),
                "wba_deny_$([System.Guid]::NewGuid().ToString('N'))"
            )
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            try {
                Set-Content -Path (Join-Path $tempDir 'manter.txt') -Value 'conteudo'
                # Raiz permitida diferente do alvo -> deve recusar e nao apagar.
                Remove-SafePath -Path $tempDir -AllowedRoot ([System.IO.Path]::GetTempPath() + 'outra_raiz_xyz') -WarningAction SilentlyContinue
                Test-Path (Join-Path $tempDir 'manter.txt') | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        It 'Deve aceitar OlderThanDays sem lancar excecao para caminho inexistente' {
            { Remove-SafePath -Path 'C:\wba_naoexiste' -OlderThanDays 30 } | Should -Not -Throw
        }
        It 'Deve preservar arquivos recentes quando OlderThanDays for informado' {
            $tempDir = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(),
                "wba_old_$([System.Guid]::NewGuid().ToString('N'))"
            )
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            try {
                $recentFile = Join-Path $tempDir 'recente.txt'
                Set-Content -Path $recentFile -Value 'recente'
                Remove-SafePath -Path $tempDir -OlderThanDays 1 -AllowedRoot $tempDir
                Test-Path $recentFile | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Invoke-EventLogMaintenance — Action None' {
        It 'Deve retornar sem erro com Action None' {
            { Invoke-EventLogMaintenance -Action None } | Should -Not -Throw
        }
        It 'Deve aceitar parametro BackupPath sem lancar excecao' {
            { Invoke-EventLogMaintenance -Action None -BackupPath 'C:\temp' } | Should -Not -Throw
        }
    }

    Context 'Invoke-EventLogMaintenance — Action Ask em contexto nao-interativo (BCK-021)' {
        It 'Nao deve lancar NullArrayIndex quando Read-Host retorna nulo (contexto nao-interativo)' {
            Mock -CommandName 'Read-Host' -ModuleName 'WbaToolkit.Maintenance' -MockWith { $null }
            { Invoke-EventLogMaintenance -Action Ask -BackupPath 'C:\temp' } | Should -Not -Throw
        }
        It 'Nao deve lancar NullArrayIndex quando Read-Host retorna string vazia' {
            Mock -CommandName 'Read-Host' -ModuleName 'WbaToolkit.Maintenance' -MockWith { '' }
            { Invoke-EventLogMaintenance -Action Ask -BackupPath 'C:\temp' } | Should -Not -Throw
        }
    }

    Context 'Invoke-FilesystemCheck — Action Skip' {
        It 'Deve retornar sem lancar excecao quando nao ha eventos de falha' {
            { Invoke-FilesystemCheck -Action Skip } | Should -Not -Throw
        }
        It 'Deve aceitar CallerScript sem lancar excecao' {
            { Invoke-FilesystemCheck -Action Skip -CallerScript 'limpeza-windows.ps1' } | Should -Not -Throw
        }
    }

    Context 'Invoke-FilesystemCheck — falhas detectadas (chkdsk mockado)' {
        BeforeAll {
            Mock -CommandName 'Get-FilesystemErrorEvent' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{
                    TimeCreated  = (Get-Date)
                    Id           = 7
                    ProviderName = 'disk'
                    Message      = 'Falha simulada no sistema de arquivos.'
                }
            }
            # chkdsk e acionado via 'cmd.exe /c echo Y | chkdsk ...': mockamos o cmd.exe
            # para nao agendar verificacao real de disco.
            Mock -CommandName 'cmd.exe' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                'O tipo do sistema de arquivos e NTFS.'
                'Chkdsk agendado (mock).'
                $global:LASTEXITCODE = 0
            }
            Mock -CommandName 'Write-MaintenanceEvent' -ModuleName 'WbaToolkit.Maintenance' -MockWith { }
        }

        It 'Action Schedule deve agendar via cmd.exe mockado, sem chkdsk real e sem lancar' {
            { Invoke-FilesystemCheck -Action Schedule } | Should -Not -Throw
            Should -Invoke -CommandName 'cmd.exe' -ModuleName 'WbaToolkit.Maintenance' -Times 1 -Exactly
            Should -Invoke -CommandName 'Write-MaintenanceEvent' -ModuleName 'WbaToolkit.Maintenance' -Times 1 -Exactly
        }

        It 'Action Skip nao deve acionar o cmd.exe (chkdsk) mesmo com falhas detectadas' {
            { Invoke-FilesystemCheck -Action Skip } | Should -Not -Throw
            Should -Invoke -CommandName 'cmd.exe' -ModuleName 'WbaToolkit.Maintenance' -Times 0 -Exactly
        }
    }

    # BCK-016: o DISM/chkdsk reais sao mockados (ModuleName) para que a suite valide
    # o contrato sem executar as ferramentas — conclui em segundos, sem prompts nem
    # efeitos no sistema (CI/SSH desassistido).
    Context 'Get-ComponentStoreInfo — DISM mockado' {
        BeforeAll {
            Mock -CommandName 'dism.exe' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                'Deployment Image Servicing and Management tool'
                'Image Version: 10.0.19041.0'
                ''
                '[==========================100.0%==========================]'
                'Component Store (WinSxS) information:'
                'Windows Explorer Reported Size of Component Store : 8.96 GB'
                'Actual Size of Component Store : 8.50 GB'
                '    Shared with Windows : 5.00 GB'
                '    Backups and Disabled Features : 1.20 GB'
                '    Cache and Temporary Data : 0.30 GB'
                'Date of Last Cleanup : 2026-06-01 03:00:00'
                'Number of Reclaimable Packages : 0'
                'Component Store Cleanup Recommended : No'
                'The operation completed successfully.'
                $global:LASTEXITCODE = 0
            }
        }

        It 'Deve invocar o DISM com /English (BCK-008, saida estavel em pt-BR)' {
            Get-ComponentStoreInfo | Out-Null
            Should -Invoke -CommandName 'dism.exe' -ModuleName 'WbaToolkit.Maintenance' `
                -ParameterFilter { $args -contains '/English' } -Times 1 -Exactly
        }

        It 'Deve parsear tamanho e recuperavel com InvariantCulture (BCK-008)' {
            $resultado = Get-ComponentStoreInfo
            $resultado.StoreSizeGB       | Should -Be 8.5
            $resultado.ReclaimableSizeGB | Should -Be 1.2
        }

        It 'Nao deve invocar o DISM real e deve retornar objeto com o contrato esperado' {
            $resultado = Get-ComponentStoreInfo
            $resultado | Should -Not -BeNullOrEmpty
            $props = $resultado.PSObject.Properties.Name
            $props | Should -Contain 'StoreSizeGB'
            $props | Should -Contain 'ReclaimableSizeGB'
            $props | Should -Contain 'RecommendedCleanup'
            $props | Should -Contain 'LastAnalysisDate'
            $props | Should -Contain 'ExitCode'
            $props | Should -Contain 'RawOutput'
            Should -Invoke -CommandName 'dism.exe' -ModuleName 'WbaToolkit.Maintenance' -Times 1 -Exactly
        }

        It 'Deve parsear a recomendacao de limpeza da saida mockada' {
            $resultado = Get-ComponentStoreInfo
            $resultado.RecommendedCleanup | Should -Be $false
            $resultado.ExitCode           | Should -Be 0
        }
    }

    Context 'Invoke-ComponentStoreCleanup — DryRun' {
        It 'Deve retornar objeto com Success=$true em DryRun' {
            $resultado = Invoke-ComponentStoreCleanup -DryRun
            $resultado         | Should -Not -BeNullOrEmpty
            $resultado.Success | Should -BeTrue
        }
        It 'Deve retornar ExitCode -1 em DryRun' {
            $resultado = Invoke-ComponentStoreCleanup -DryRun
            $resultado.ExitCode | Should -Be -1
        }
        It 'Deve retornar Level Standard quando nao especificado' {
            $resultado = Invoke-ComponentStoreCleanup -DryRun
            $resultado.Level | Should -Be 'Standard'
        }
        It 'Deve retornar Level Aggressive quando especificado' {
            $resultado = Invoke-ComponentStoreCleanup -Level Aggressive -DryRun
            $resultado.Level   | Should -Be 'Aggressive'
            $resultado.Success | Should -BeTrue
        }
        It 'Deve retornar SpaceFreedMB zero em DryRun' {
            $resultado = Invoke-ComponentStoreCleanup -DryRun
            $resultado.SpaceFreedMB | Should -Be 0
        }
        It 'Deve possuir todas as propriedades esperadas no retorno' {
            $resultado = Invoke-ComponentStoreCleanup -DryRun
            $props = $resultado.PSObject.Properties.Name
            $props | Should -Contain 'Level'
            $props | Should -Contain 'ExitCode'
            $props | Should -Contain 'SpaceFreedMB'
            $props | Should -Contain 'RawOutput'
            $props | Should -Contain 'Success'
        }
        It 'RawOutput deve indicar DryRun' {
            $resultado = Invoke-ComponentStoreCleanup -DryRun
            $resultado.RawOutput | Should -Match 'DryRun'
        }
    }

    Context 'Invoke-ComponentStoreCleanup — execucao real com DISM mockado' {
        BeforeAll {
            Mock -CommandName 'dism.exe' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                'Deployment Image Servicing and Management tool'
                '[==========================100.0%==========================]'
                'The operation completed successfully.'
                $global:LASTEXITCODE = 0
            }
            Mock -CommandName 'Get-DiskInfo' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{ TotalGB = 127.0; UsadoGB = 35.0; LivreGB = 92.0 }
            }
        }

        It 'Deve executar o caminho real sem invocar o DISM real e retornar Success' {
            $resultado = Invoke-ComponentStoreCleanup -Confirm:$false
            $resultado.Success  | Should -BeTrue
            $resultado.ExitCode | Should -Be 0
            $resultado.Level    | Should -Be 'Standard'
            Should -Invoke -CommandName 'dism.exe' -ModuleName 'WbaToolkit.Maintenance' -Times 1 -Exactly
        }

        It 'Nivel Aggressive deve acionar o DISM mockado uma vez (sem ResetBase real)' {
            $resultado = Invoke-ComponentStoreCleanup -Level Aggressive -Confirm:$false -WarningAction SilentlyContinue
            $resultado.Success | Should -BeTrue
            $resultado.Level   | Should -Be 'Aggressive'
            Should -Invoke -CommandName 'dism.exe' -ModuleName 'WbaToolkit.Maintenance' -Times 1 -Exactly
        }
    }

    Context 'Invoke-SysprepPreparation - DryRun' {
        It 'Deve retornar resultados DryRun para cada arquivo .reg no diretorio' {
            $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "wba_prep_$([System.Guid]::NewGuid().ToString('N'))")
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            try {
                Set-Content (Join-Path $tempDir 'Tweak_Alpha.reg') "Windows Registry Editor Version 5.00`r`n" -Encoding ASCII
                Set-Content (Join-Path $tempDir 'Tweak_Beta.reg')  "Windows Registry Editor Version 5.00`r`n" -Encoding ASCII

                $resultados = @(Invoke-SysprepPreparation -RegFilesDirectory $tempDir -DryRun)

                $resultados.Count               | Should -Be 2
                $resultados[0].Message          | Should -Be 'DryRun.'
                $resultados[1].Message          | Should -Be 'DryRun.'
                $resultados | ForEach-Object { $_.Success | Should -BeTrue }
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        It 'Deve retornar array vazio quando o diretorio nao tem arquivos .reg' {
            $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "wba_empty_$([System.Guid]::NewGuid().ToString('N'))")
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            try {
                $resultados = @(Invoke-SysprepPreparation -RegFilesDirectory $tempDir -DryRun)
                $resultados.Count | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        It 'Deve processar arquivos em ordem alfabetica' {
            $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "wba_ord_$([System.Guid]::NewGuid().ToString('N'))")
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            try {
                Set-Content (Join-Path $tempDir 'C_Tweak.reg') "Windows Registry Editor Version 5.00`r`n" -Encoding ASCII
                Set-Content (Join-Path $tempDir 'A_Tweak.reg') "Windows Registry Editor Version 5.00`r`n" -Encoding ASCII
                Set-Content (Join-Path $tempDir 'B_Tweak.reg') "Windows Registry Editor Version 5.00`r`n" -Encoding ASCII

                $resultados = @(Invoke-SysprepPreparation -RegFilesDirectory $tempDir -DryRun)

                $resultados[0].Tweak | Should -Be 'A_Tweak'
                $resultados[1].Tweak | Should -Be 'B_Tweak'
                $resultados[2].Tweak | Should -Be 'C_Tweak'
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'ConvertTo-StoreSizeGB - parsing independente de cultura (BCK-008)' {
        It 'Converte "8.50" GB com ponto decimal (InvariantCulture)' {
            InModuleScope WbaToolkit.Maintenance {
                ConvertTo-StoreSizeGB -Value '8.50' -Unit 'GB' | Should -Be 8.5
            }
        }
        It 'Ignora separador de milhar e converte MB para GB' {
            InModuleScope WbaToolkit.Maintenance {
                ConvertTo-StoreSizeGB -Value '1,024' -Unit 'MB' | Should -Be 1
            }
        }
        It 'Retorna nulo para valor nao numerico' {
            InModuleScope WbaToolkit.Maintenance {
                ConvertTo-StoreSizeGB -Value 'N/A' -Unit 'GB' | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Test-SysprepEnvironment - edicao e CIM (BCK-011)' {
        It 'Inclui a propriedade Edition no retorno' {
            (Test-SysprepEnvironment).PSObject.Properties.Name | Should -Contain 'Edition'
        }
        It 'Invalida quando o CIM nao retorna o sistema operacional' {
            Mock -CommandName 'Get-CimInstanceSafe' -ModuleName 'WbaToolkit.Maintenance' -MockWith { $null }
            $r = Test-SysprepEnvironment
            $r.IsValid              | Should -BeFalse
            ($r.Errors -join ' ')   | Should -Match 'CIM'
        }
        It 'Invalida edicao Home (Core)' {
            Mock -CommandName 'Get-ItemProperty' -ModuleName 'WbaToolkit.Maintenance' `
                -ParameterFilter { $Name -eq 'EditionID' } -MockWith {
                    [pscustomobject]@{ EditionID = 'Core' }
                }
            $r = Test-SysprepEnvironment
            ($r.Errors -join ' ') | Should -Match 'Edicao do Windows nao suportada'
        }
    }

    Context 'Invoke-RegFileImport - reescrita de hive e validacao (BCK-011)' {
        It 'Reescreve HKEY_CURRENT_USER e importa (.reg UTF-16 LE, reg mockado)' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'reg' -MockWith { $global:LASTEXITCODE = 0 }
                $f = Join-Path ([System.IO.Path]::GetTempPath()) "wba_rfi_$([System.Guid]::NewGuid().ToString('N')).reg"
                [System.IO.File]::WriteAllText(
                    $f,
                    "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Software\WBA\T]`r`n",
                    [System.Text.Encoding]::Unicode)
                try {
                    { Invoke-RegFileImport -RegFilePath $f -MountPoint 'WBA_DefaultProfile' } | Should -Not -Throw
                    Should -Invoke -CommandName 'reg' -Times 1 -Exactly
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
        It 'Lanca e nao importa quando nao ha referencia de hive para substituir' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'reg' -MockWith { $global:LASTEXITCODE = 0 }
                $f = Join-Path ([System.IO.Path]::GetTempPath()) "wba_rfi_$([System.Guid]::NewGuid().ToString('N')).reg"
                [System.IO.File]::WriteAllText(
                    $f,
                    "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_LOCAL_MACHINE\Software\WBA\T]`r`n",
                    [System.Text.Encoding]::Unicode)
                try {
                    { Invoke-RegFileImport -RegFilePath $f -MountPoint 'WBA_DefaultProfile' } |
                        Should -Throw '*Nenhuma referencia de hive*'
                    Should -Invoke -CommandName 'reg' -Times 0 -Exactly
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    Context 'Read-RegFileContent - deteccao de encoding (BCK-022)' {
        It 'Le arquivo ASCII com hive de usuario' {
            InModuleScope WbaToolkit.Maintenance {
                $f = [System.IO.Path]::GetTempFileName() + '.reg'
                try {
                    Set-Content -Path $f -Encoding ASCII -Value "Windows Registry Editor Version 5.00`r`n`r`n[hkey_users\default\Software\WBA\Teste]`r`n"
                    $conteudo = Read-RegFileContent -Path $f
                    $conteudo | Should -Match 'hkey_users\\default'
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
        It 'Le arquivo UTF-8 sem BOM' {
            InModuleScope WbaToolkit.Maintenance {
                $f = [System.IO.Path]::GetTempFileName() + '.reg'
                try {
                    $enc = New-Object System.Text.UTF8Encoding($false)
                    [System.IO.File]::WriteAllText($f, "Windows Registry Editor Version 5.00`r`n`r`n[hkey_users\default\Software\WBA\Teste]`r`n", $enc)
                    $conteudo = Read-RegFileContent -Path $f
                    $conteudo | Should -Match 'hkey_users\\default'
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
        It 'Le arquivo UTF-8 com BOM' {
            InModuleScope WbaToolkit.Maintenance {
                $f = [System.IO.Path]::GetTempFileName() + '.reg'
                try {
                    $enc = New-Object System.Text.UTF8Encoding($true)
                    [System.IO.File]::WriteAllText($f, "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Software\WBA\Teste]`r`n", $enc)
                    $conteudo = Read-RegFileContent -Path $f
                    $conteudo | Should -Match 'HKEY_CURRENT_USER'
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
        It 'Le arquivo UTF-16 LE com BOM' {
            InModuleScope WbaToolkit.Maintenance {
                $f = [System.IO.Path]::GetTempFileName() + '.reg'
                try {
                    [System.IO.File]::WriteAllText($f, "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_USERS\.DEFAULT\Software\WBA\Teste]`r`n", [System.Text.Encoding]::Unicode)
                    $conteudo = Read-RegFileContent -Path $f
                    $conteudo | Should -Match 'HKEY_USERS'
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
        It 'Lanca erro para arquivo vazio' {
            InModuleScope WbaToolkit.Maintenance {
                $f = [System.IO.Path]::GetTempFileName() + '.reg'
                try {
                    [System.IO.File]::WriteAllBytes($f, [byte[]]@())
                    { Read-RegFileContent -Path $f } | Should -Throw '*vazio*'
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    Context 'Invoke-RegFileImport - ASCII aceito e substituicao validada (BCK-022)' {
        It 'Aceita .reg ASCII com hkey_users\default sem falso negativo de hive' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'reg' -MockWith { $global:LASTEXITCODE = 0 }
                $f = Join-Path ([System.IO.Path]::GetTempPath()) "wba_ascii_$([System.Guid]::NewGuid().ToString('N')).reg"
                Set-Content -Path $f -Encoding ASCII -Value "Windows Registry Editor Version 5.00`r`n`r`n[hkey_users\default\Software\WBA\T]`r`n"
                try {
                    { Invoke-RegFileImport -RegFilePath $f -MountPoint 'WBA_DefaultProfile' } | Should -Not -Throw
                    Should -Invoke -CommandName 'reg' -Times 1 -Exactly
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
        It 'Arquivo temporario entregue ao reg contem HKEY_USERS\MountPoint substituido' {
            InModuleScope WbaToolkit.Maintenance {
                $script:capturedContent = $null
                Mock -CommandName 'reg' -MockWith {
                    $importArg = $args | Where-Object { $_ -match '\.reg$' }
                    if ($importArg -and (Test-Path -LiteralPath $importArg)) {
                        $script:capturedContent = [System.IO.File]::ReadAllText($importArg, [System.Text.Encoding]::Unicode)
                    }
                    $global:LASTEXITCODE = 0
                }
                $f = Join-Path ([System.IO.Path]::GetTempPath()) "wba_subst_$([System.Guid]::NewGuid().ToString('N')).reg"
                Set-Content -Path $f -Encoding ASCII -Value "Windows Registry Editor Version 5.00`r`n`r`n[hkey_users\default\Software\WBA\T]`r`n"
                try {
                    Invoke-RegFileImport -RegFilePath $f -MountPoint 'WBA_DefaultProfile'
                    $script:capturedContent | Should -Not -BeNullOrEmpty
                    $script:capturedContent | Should -Match 'HKEY_USERS\\WBA_DefaultProfile'
                    $script:capturedContent | Should -Not -Match '(?i)hkey_users\\\.?default(?!\w)'
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
        It 'Rejeita .reg somente HKLM' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'reg' -MockWith { $global:LASTEXITCODE = 0 }
                $f = Join-Path ([System.IO.Path]::GetTempPath()) "wba_hklm_$([System.Guid]::NewGuid().ToString('N')).reg"
                Set-Content -Path $f -Encoding ASCII -Value "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_LOCAL_MACHINE\Software\WBA\T]`r`n"
                try {
                    { Invoke-RegFileImport -RegFilePath $f -MountPoint 'WBA_DefaultProfile' } | Should -Throw '*hive de usuario*'
                    Should -Invoke -CommandName 'reg' -Times 0 -Exactly
                }
                finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    Context 'Get-SysprepAppxProvisioningIssue - validacao Appx (BCK-022)' {
        It 'Retorna lista vazia quando todos os pacotes estao provisionados' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'Get-AppxProvisionedPackage' -MockWith {
                    [pscustomobject]@{ DisplayName = 'Microsoft.Exemplo' }
                }
                Mock -CommandName 'Get-AppxPackage' -MockWith {
                    [pscustomobject]@{
                        Name = 'Microsoft.Exemplo'
                        PackageFullName = 'Microsoft.Exemplo_1.0.0_x64__abc'
                        Version = '1.0.0'
                        Architecture = 'X64'
                        Publisher = 'CN=Microsoft'
                        PackageUserInformation = @()
                    }
                }
                $resultado = @(Get-SysprepAppxProvisioningIssue)
                $resultado.Count | Should -Be 0
            }
        }
        It 'Detecta pacote instalado para usuario e nao provisionado' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'Get-AppxProvisionedPackage' -MockWith { @() }
                Mock -CommandName 'Get-AppxPackage' -MockWith {
                    [pscustomobject]@{
                        Name = 'Microsoft.LanguageExperiencePackpt-BR'
                        PackageFullName = 'Microsoft.LanguageExperiencePackpt-BR_19041.80.279.0_neutral__8wekyb3d8bbwe'
                        Version = '19041.80.279.0'
                        Architecture = 'Neutral'
                        Publisher = 'CN=Microsoft'
                        PackageUserInformation = @()
                    }
                }
                $resultado = @(Get-SysprepAppxProvisioningIssue)
                $resultado.Count        | Should -BeGreaterThan 0
                $resultado[0].Severity  | Should -Be 'Blocker'
                $resultado[0].Reason    | Should -Be 'InstalledForUserButNotProvisioned'
                $resultado[0].Name      | Should -Be 'Microsoft.LanguageExperiencePackpt-BR'
            }
        }
        It 'Lanca erro bloqueante quando Get-AppxPackage falha' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'Get-AppxProvisionedPackage' -MockWith { @() }
                Mock -CommandName 'Get-AppxPackage' -MockWith { throw 'Falha simulada' }
                { Get-SysprepAppxProvisioningIssue } | Should -Throw '*Sysprep bloqueada por seguranca*'
            }
        }
        It 'Lanca erro bloqueante quando Get-AppxProvisionedPackage falha' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'Get-AppxProvisionedPackage' -MockWith { throw 'Falha simulada' }
                { Get-SysprepAppxProvisioningIssue } | Should -Throw '*Sysprep bloqueada por seguranca*'
            }
        }
    }

    Context 'Test-SysprepEnvironment - SysprepBlockers (BCK-022)' {
        It 'Deve ter propriedade SysprepBlockers no retorno' {
            $r = Test-SysprepEnvironment
            $r.PSObject.Properties.Name | Should -Contain 'SysprepBlockers'
        }
        It 'SysprepBlockers deve ser array' {
            $r = Test-SysprepEnvironment
            $r.SysprepBlockers.GetType().IsArray | Should -BeTrue
        }
        It 'Com bloqueador Appx: IsValid false e SysprepBlockers nao vazio' {
            Mock -CommandName 'Get-SysprepAppxProvisioningIssue' -ModuleName 'WbaToolkit.Maintenance' -MockWith {
                [pscustomobject]@{
                    Name            = 'Microsoft.LanguageExperiencePackpt-BR'
                    PackageFullName = 'Microsoft.LanguageExperiencePackpt-BR_19041.80.279.0_neutral__8wekyb3d8bbwe'
                    Version         = '19041.80.279.0'
                    Architecture    = 'Neutral'
                    Publisher       = 'CN=Microsoft'
                    Users           = @()
                    Reason          = 'InstalledForUserButNotProvisioned'
                    Severity        = 'Blocker'
                }
            }
            $r = Test-SysprepEnvironment
            $r.IsValid               | Should -BeFalse
            $r.SysprepBlockers.Count | Should -BeGreaterThan 0
            ($r.Errors -join ' ')    | Should -Match 'Appx'
        }
        It 'Sem bloqueador Appx: SysprepBlockers vazio' {
            Mock -CommandName 'Get-SysprepAppxProvisioningIssue' -ModuleName 'WbaToolkit.Maintenance' -MockWith { @() }
            $r = Test-SysprepEnvironment
            $r.SysprepBlockers.Count | Should -Be 0
        }
    }

    Context 'Invoke-WithDefaultUserHive - unload com retry e erro elevavel (BCK-009)' {
        It 'Desmonta com sucesso e retorna o valor do ScriptBlock' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'Get-DefaultUserHivePath' -MockWith { 'C:\fake\NTUSER.DAT' }
                Mock -CommandName 'Test-Path' -MockWith { $false }
                Mock -CommandName 'reg' -MockWith { $global:LASTEXITCODE = 0 }
                Invoke-WithDefaultUserHive -ScriptBlock { param($m) "montado:$m" } |
                    Should -Be 'montado:WBA_DefaultProfile'
            }
        }
        It 'Repete o unload 3x e lanca erro elevavel quando falha' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'Get-DefaultUserHivePath' -MockWith { 'C:\fake\NTUSER.DAT' }
                Mock -CommandName 'Test-Path' -MockWith { $false }
                Mock -CommandName 'Start-Sleep' -MockWith { }
                Mock -CommandName 'reg' -MockWith {
                    if ($args -contains 'unload') { $global:LASTEXITCODE = 1; return 'erro unload' }
                    $global:LASTEXITCODE = 0
                }
                { Invoke-WithDefaultUserHive -ScriptBlock { 'ok' } } | Should -Throw '*desmontar*'
                Should -Invoke -CommandName 'reg' -ParameterFilter { $args -contains 'unload' } -Times 3 -Exactly
            }
        }
        It 'Limpa montagem stale antes de carregar' {
            InModuleScope WbaToolkit.Maintenance {
                Mock -CommandName 'Get-DefaultUserHivePath' -MockWith { 'C:\fake\NTUSER.DAT' }
                Mock -CommandName 'Test-Path' -MockWith { $true }
                Mock -CommandName 'Write-Warn' -MockWith { }
                Mock -CommandName 'reg' -MockWith { $global:LASTEXITCODE = 0 }
                Invoke-WithDefaultUserHive -ScriptBlock { 'x' } | Out-Null
                Should -Invoke -CommandName 'reg' -ParameterFilter { $args -contains 'unload' } -Times 2 -Exactly
            }
        }
    }
}
