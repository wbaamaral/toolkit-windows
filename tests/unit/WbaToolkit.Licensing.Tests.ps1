#requires -version 5.1

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulesRoot = Join-Path $repoRoot 'modules'
    $env:PSModulePath = "$modulesRoot$([IO.Path]::PathSeparator)$env:PSModulePath"
    Import-Module (Join-Path $modulesRoot 'WbaToolkit.Core/WbaToolkit.Core.psd1') -Force

    # Linux/pwsh não possui o cmdlet Windows; o stub permite que Pester 5
    # faça Mock sem jamais tocar CIM real. No Windows o cmdlet nativo permanece.
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Get-CimInstance { throw 'Get-CimInstance indisponível neste ambiente de testes.' }
    }

    $licensingRoot = Join-Path $modulesRoot 'WbaToolkit.Licensing'
    $script:invokeSlmgrContent = Get-Content (Join-Path $licensingRoot 'Private/Invoke-Slmgr.ps1') -Raw
    $script:manifestContent = Get-Content (Join-Path $licensingRoot 'WbaToolkit.Licensing.psd1') -Raw
    Get-ChildItem (Join-Path $licensingRoot 'Private') -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    Get-ChildItem (Join-Path $licensingRoot 'Public') -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}

Describe 'WbaToolkit.Licensing — estrutura BCK-040' {
    It 'Possui manifesto PowerShell 5.1 e dependência Core' {
        $script:manifestContent | Should -Match 'PowerShellVersion\s*=\s*''5\.1'''
        $script:manifestContent | Should -Match 'WbaToolkit\.Core'
    }

    It 'Exporta as tres funcoes publicas do modulo' {
        Test-Path (Join-Path $repoRoot 'modules/WbaToolkit.Licensing/WbaToolkit.Licensing.psm1') | Should -BeTrue
        $script:manifestContent | Should -Match 'FunctionsToExport\s*=\s*@\('
        $script:manifestContent | Should -Match "'Backup-LicenseState'"
        $script:manifestContent | Should -Match "'Get-LicenseCycleStatus'"
        $script:manifestContent | Should -Match "'Restore-LicenseState'"
    }
}

Describe 'Invoke-Slmgr' {
    It 'Usa cscript //nologo e slmgr.vbs, sem chamada direta em funções públicas' {
        $script:invokeSlmgrContent | Should -Match 'cscript\.exe'
        $script:invokeSlmgrContent | Should -Match '//nologo'
        $script:invokeSlmgrContent | Should -Match 'System32\\slmgr\.vbs'
        $script:invokeSlmgrContent | Should -Match 'ExitCode'
        $script:invokeSlmgrContent | Should -Match 'StdOut'
        $script:invokeSlmgrContent | Should -Match 'StdErr'
        $script:invokeSlmgrContent | Should -Match 'Lines'
    }

    It 'Retorna estrutura segura quando cscript não existe no Linux' {
        $result = Invoke-Slmgr -ArgumentList '/dli'
        $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
        $result.PSObject.Properties.Name | Should -Contain 'Lines'
        $result.ExitCode | Should -Not -BeNullOrEmpty
    }
}

Describe 'Helpers de consulta e normalização' {
    It 'Aceita chave válida em maiúsculas e minúsculas' {
        Test-ProductKeyFormat -ProductKey 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' | Should -BeTrue
        Test-ProductKeyFormat -ProductKey 'aaaaa-bbbbb-ccccc-ddddd-eeeee' | Should -BeTrue
    }

    It 'Rejeita chave com quantidade de grupos incorreta' {
        Test-ProductKeyFormat -ProductKey 'AAAAA-BBBBB-CCCCC-DDDDD' | Should -BeFalse
        Test-ProductKeyFormat -ProductKey 'AAAAA_BBBBB_CCCCC_DDDDD_EEEEE' | Should -BeFalse
    }

    It 'Converte produto CIM em LicenseInfo com canal e parcial' {
        $product = [pscustomobject]@{
            Name = 'Windows 10 Pro'; Description = 'RETAIL channel'; LicenseStatus = 1
            PartialProductKey = 'ABCDE'; ID = 'id'; InstallationID = 'install'; ApplicationId = 'app'; Version = '10.0'
        }
        $service = [pscustomobject]@{ KeyManagementServiceMachine = $null; KeyManagementServicePort = $null; RemainingWindowsReArmCount = 3 }
        $info = ConvertTo-LicenseInfoObject -Product $product -Service $service
        $info.Licenca.Canal | Should -Be 'Retail'
        $info.Licenca.Status | Should -Be 'Licensed'
        $info.Licenca.PartialProductKey | Should -Be 'ABCDE'
        $info.Rearm.Restante | Should -Be 3
    }

    It 'Classifica canal KMS e OEM' {
        $kms = [pscustomobject]@{ Name = 'Windows VOLUME_KMSCLIENT channel'; Description = ''; LicenseStatus = 1; PartialProductKey = 'ABCDE' }
        $oem = [pscustomobject]@{ Name = 'Windows OEM_DM'; Description = 'OEM_DM channel'; LicenseStatus = 1; PartialProductKey = 'ABCDE' }
        (ConvertTo-LicenseInfoObject -Product $kms).Licenca.Canal | Should -Be 'KMS'
        (ConvertTo-LicenseInfoObject -Product $oem).Licenca.Canal | Should -Be 'OEM'
    }
}

Describe 'Get-LicenseHardwareContext' {
    It 'Calcula HWID determinístico e detecta baseline divergente' {
        Mock Get-CimInstance {
            param($ClassName)
            switch ($ClassName) {
                'Win32_ComputerSystemProduct' { [pscustomobject]@{ UUID = 'uuid-1'; Manufacturer = 'WBA'; Name = 'Lab' } }
                'Win32_BaseBoard' { [pscustomobject]@{ SerialNumber = 'board-1'; Manufacturer = 'WBA'; Product = 'Board' } }
                'Win32_BIOS' { [pscustomobject]@{ SerialNumber = 'bios-1'; Manufacturer = 'WBA'; SMBIOSBIOSVersion = '1.0' } }
            }
        }
        $baseline = Join-Path $TestDrive 'hwid-baseline.json'
        '{"Hwid":"outro"}' | Set-Content -LiteralPath $baseline
        $context = Get-LicenseHardwareContext -BaselinePath $baseline
        $context.HwidAtual.Length | Should -Be 64
        $context.HardwareAlterado | Should -BeTrue
    }
}

Describe 'Get-OemProductKey' {
    It 'Persiste somente os cinco últimos caracteres' {
        Mock Get-ItemProperty { [pscustomobject]@{ BackupProductKeyDefault = 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' } }
        $oem = Get-OemProductKey
        $oem.PartialOemKey | Should -Be 'EEEEE'
        $oem.PartialOemKey | Should -Not -Match '-'
    }
}

Describe 'Test-LicenseAdminContext' {
    It 'Falha fechado quando CIM falha' {
        Mock Get-CimInstance { throw 'CIM indisponível' }
        { Test-LicenseAdminContext } | Should -Throw
    }
}

Describe 'Get-WindowsLicenseInfo (RF-01)' {
    BeforeAll {
        Mock Get-LicenseHardwareContext { [pscustomobject]@{ HwidAtual = ('a' * 64); HwidBaseline = $null; HardwareAlterado = $false } }
        Mock Invoke-Slmgr { [pscustomobject]@{ ExitCode = 0; StdOut = @(); StdErr = @(); Lines = @() } }
    }

    function global:New-TestLicenseProduct {
        param([string]$Name, [string]$Description)
        [pscustomobject]@{
            Name = $Name; Description = $Description; LicenseStatus = 1
            PartialProductKey = 'ABCDE'; ID = 'id'; InstallationID = 'inst'
            ApplicationId = 'app'; Version = '10.0'
        }
    }

    It 'Consolida CIM + slmgr em objeto LicenseInfo' {
        Mock Get-SoftwareLicensingProduct { New-TestLicenseProduct -Name 'Windows 10 Pro' -Description 'RETAIL channel' }
        Mock Get-SoftwareLicensingService { [pscustomobject]@{ KeyManagementServiceMachine = $null; KeyManagementServicePort = $null; RemainingWindowsReArmCount = 3 } }

        $info = Get-WindowsLicenseInfo
        $info.Licenca.Canal | Should -Be 'Retail'
        $info.Licenca.Status | Should -Be 'Licensed'
        $info.Licenca.PartialProductKey | Should -Be 'ABCDE'
        $info.Windows.Edicao | Should -Be 'Windows 10 Pro'
        $info.Hardware.HardwareAlterado | Should -BeFalse
    }

    It 'Marca HardwareAlterado quando HWID diverge' {
        Mock Get-SoftwareLicensingProduct { New-TestLicenseProduct -Name 'Windows 10 Pro' -Description 'RETAIL channel' }
        Mock Get-SoftwareLicensingService { [pscustomobject]@{ KeyManagementServiceMachine = $null; KeyManagementServicePort = $null; RemainingWindowsReArmCount = 3 } }
        Mock Get-LicenseHardwareContext { [pscustomobject]@{ HwidAtual = ('b' * 64); HwidBaseline = ('a' * 64); HardwareAlterado = $true } }

        $info = Get-WindowsLicenseInfo
        $info.Hardware.HardwareAlterado | Should -BeTrue
        $info.Hardware.HwidBaseline | Should -Be ('a' * 64)
    }

    It 'Retorna Canal=OEM quando Description tem OEM_DM' {
        Mock Get-SoftwareLicensingProduct { New-TestLicenseProduct -Name 'Windows 10 Home' -Description 'OEM_DM channel' }
        Mock Get-SoftwareLicensingService { [pscustomobject]@{ KeyManagementServiceMachine = $null; KeyManagementServicePort = $null; RemainingWindowsReArmCount = 3 } }

        (Get-WindowsLicenseInfo).Licenca.Canal | Should -Be 'OEM'
    }

    It 'Retorna Canal=KMS para VOLUME_KMSCLIENT channel' {
        Mock Get-SoftwareLicensingProduct { New-TestLicenseProduct -Name 'Windows VOLUME_KMSCLIENT channel' -Description 'VOLUME_KMSCLIENT channel' }
        Mock Get-SoftwareLicensingService { [pscustomobject]@{ KeyManagementServiceMachine = 'kms.wba.local'; KeyManagementServicePort = 1688; RemainingWindowsReArmCount = 3 } }

        $info = Get-WindowsLicenseInfo
        $info.Licenca.Canal | Should -Be 'KMS'
        $info.Kms.Servidor | Should -Be 'kms.wba.local'
        $info.Kms.Porta | Should -Be 1688
    }
}

Describe 'Resolve-LicenseError (RF-02)' {
    It 'Resolve 0xC004F034 pela tabela' {
        $r = Resolve-LicenseError -Codigo '0xC004F034'
        $r.Significado | Should -Not -BeNullOrEmpty
        $r.Causas | Should -Not -BeNullOrEmpty
        $r.Procedimentos | Should -Not -BeNullOrEmpty
        $r.Codigo | Should -Be '0xC004F034'
    }

    It 'Retorna Não catalogado para código desconhecido' {
        $r = Resolve-LicenseError -Codigo '0xC004FA99'
        $r.Significado | Should -Be 'Não catalogado'
    }

    It 'Rejeita código fora do formato 0xXXXXXXXX' {
        { Resolve-LicenseError -Codigo 'C004F034' } | Should -Throw
        { Resolve-LicenseError -Codigo '0xC004' } | Should -Throw
    }

    It 'Cobre as demais entradas da tabela canônica' {
        foreach ($codigo in @('0xC004C003', '0xC004C008', '0xC004F050', '0x803FA067', '0x8007232B', '0xC004F074', '0xC004F042', '0xC004C020', '0xC004F200', '0x80070422')) {
            $r = Resolve-LicenseError -Codigo $codigo
            $r.Significado | Should -Not -BeNullOrEmpty -Because "codigo $codigo deve estar na tabela"
            $r.Severidade | Should -BeIn @('informativo', 'aviso', 'erro', 'critico')
        }
    }
}

Describe 'Get-LicenseCycleStatus' {
    BeforeAll {
        function global:New-CycleProduct {
            param([int]$LicenseStatus, [string]$Name = 'Windows 10 Pro', [string]$Description = 'RETAIL channel')
            [pscustomobject]@{
                Name = $Name; Description = $Description; LicenseStatus = $LicenseStatus
                PartialProductKey = 'ABCDE'; ID = 'id'; InstallationID = 'inst'
                ApplicationId = 'app'; Version = '10.0'
            }
        }
        function global:New-CycleService {
            param([int]$Rearm = 3)
            [pscustomobject]@{ KeyManagementServiceMachine = $null; KeyManagementServicePort = $null; RemainingWindowsReArmCount = $Rearm }
        }
    }

    It 'Retorna NoProduct quando nenhum produto encontrado' {
        Mock Get-SoftwareLicensingProduct { return @() }
        Mock Invoke-Slmgr { [pscustomobject]@{ ExitCode = 0; Lines = @() } }

        $c = Get-LicenseCycleStatus
        $c.State | Should -Be 'NoProduct'
        $c.StateCode | Should -Be -1
    }

    It 'Classifica Licensed e recomenda acao' {
        Mock Get-SoftwareLicensingProduct { New-CycleProduct -LicenseStatus 1 }
        Mock Get-SoftwareLicensingService { New-CycleService }
        Mock Invoke-Slmgr {
            if ($ArgumentList -contains '/xpr') {
                [pscustomobject]@{ ExitCode = 0; Lines = @('Windows está ativado', '12/30/2027 00:00:00') }
            } else {
                [pscustomobject]@{ ExitCode = 0; Lines = @('some output') }
            }
        }

        $c = Get-LicenseCycleStatus
        $c.State | Should -Be 'Licensed'
        $c.Channel | Should -Be 'Retail'
        $c.Recommendations | Should -Contain 'Sistema ativado e licenciado. Nenhuma acao necessaria.'
    }

    It 'Classifica GracePeriod com dias restantes' {
        Mock Get-SoftwareLicensingProduct { New-CycleProduct -LicenseStatus 2 }
        Mock Get-SoftwareLicensingService { New-CycleService -Rearm 1 }
        Mock Invoke-Slmgr {
            if ($ArgumentList -contains '/xpr') {
                [pscustomobject]@{ ExitCode = 0; Lines = @('10 dias restante') }
            } else {
                [pscustomobject]@{ ExitCode = 0; Lines = @('some output') }
            }
        }

        $c = Get-LicenseCycleStatus
        $c.State | Should -Be 'GracePeriod'
        $c.DaysRemaining | Should -Be 10
        $c.RearmCount | Should -Be 1
    }

    It 'Classifica NonGenuine' {
        Mock Get-SoftwareLicensingProduct { New-CycleProduct -LicenseStatus 4 }
        Mock Get-SoftwareLicensingService { New-CycleService }
        Mock Invoke-Slmgr { [pscustomobject]@{ ExitCode = 0; Lines = @('some output') } }

        $c = Get-LicenseCycleStatus
        $c.State | Should -Be 'NonGenuine'
        $c.Recommendations | Should -Contain 'Sistema marcado como nao genuino. Licenciamento invalido detectado.'
    }
}

Describe 'Backup-LicenseState' {
    It 'Cria diretorio e salva snapshot JSON + README com -Path' {
        Mock Get-SoftwareLicensingProduct { New-CycleProduct -LicenseStatus 1 }
        Mock Get-SoftwareLicensingService { New-CycleService }
        Mock Invoke-Slmgr { [pscustomobject]@{ ExitCode = 0; Lines = @('ok') } }
        Mock Get-LicenseHardwareContext { [pscustomobject]@{ HwidAtual = ('a' * 64) } }
        Mock Get-OemProductKey { [pscustomobject]@{ PartialOemKey = 'EEEEE' } }

        $backup = Backup-LicenseState -Path (Join-Path $TestDrive 'bkp')
        $backup.Success | Should -BeTrue
        Test-Path -LiteralPath $backup.JsonPath | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $backup.BackupPath 'README.txt') | Should -BeTrue
        $backup.Snapshot.ComputerName | Should -Be $env:COMPUTERNAME
        $backup.Snapshot.OemKey.PartialOemKey | Should -Be 'EEEEE'
    }

    It 'Suporta snapshot sem produto (null-safe)' {
        Mock Get-SoftwareLicensingProduct { return @() }
        Mock Get-SoftwareLicensingService { New-CycleService }
        Mock Invoke-Slmgr { [pscustomobject]@{ ExitCode = 0; Lines = @() } }
        Mock Get-LicenseHardwareContext { [pscustomobject]@{ HwidAtual = ('a' * 64) } }
        Mock Get-OemProductKey { $null }

        $backup = Backup-LicenseState -Path (Join-Path $TestDrive 'bkp2')
        $backup.Success | Should -BeTrue
        $backup.Snapshot.Product | Should -BeNullOrEmpty
    }
}

Describe 'Restore-LicenseState' {
    It 'Rejeita uso sem BackupPath nem AutoDiscover' {
        $r = Restore-LicenseState
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'Use -BackupPath'
    }

    It 'Reporta backup nao encontrado' {
        $r = Restore-LicenseState -BackupPath (Join-Path $TestDrive 'nao-existe')
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'nao encontrado'
    }

    It 'Rejeita backup invalido (JSON sem campos obrigatorios)' {
        $bad = Join-Path $TestDrive 'bad.json'
        '{"foo":"bar"}' | Set-Content -LiteralPath $bad -Encoding UTF8
        Mock Get-SoftwareLicensingProduct { New-CycleProduct -LicenseStatus 1 }
        Mock Get-SoftwareLicensingService { New-CycleService }
        Mock Get-LicenseCycleStatus { [pscustomobject]@{ Channel = 'Retail' } }

        $r = Restore-LicenseState -BackupPath $bad
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'Backup invalido'
    }

    It 'Detecta diffs e restaura KMS com -Force' {
        $good = Join-Path $TestDrive 'good.json'
        $snapshot = [pscustomobject]@{
            BackupTimestamp = '2026-07-30T00:00:00'
            ComputerName   = 'TEST-PC'
            Product        = [pscustomobject]@{ PartialProductKey = 'XXXXX'; Name = 'Windows 10 Pro'; Description = 'RETAIL channel'; LicenseStatus = 1; ID = 'id'; ApplicationId = 'app'; InstallationID = 'inst'; Version = '10.0' }
            Service        = [pscustomobject]@{ KeyManagementServiceMachine = 'kms.antigo'; KeyManagementServicePort = 1688; RemainingWindowsReArmCount = 3 }
            LicenseInfo    = [pscustomobject]@{ Licenca = [pscustomobject]@{ Canal = 'Retail'; Status = 'Licensed'; PartialProductKey = 'XXXXX' } }
            Hardware       = [pscustomobject]@{ HwidAtual = ('a' * 64) }
        }
        $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $good -Encoding UTF8

        Mock Get-SoftwareLicensingProduct { New-CycleProduct -LicenseStatus 1 }
        Mock Get-SoftwareLicensingService { New-CycleService }
        Mock Get-LicenseCycleStatus { [pscustomobject]@{ Channel = 'KMS' } }
        Mock Get-LicenseHardwareContext { [pscustomobject]@{ HwidAtual = ('a' * 64) } }
        Mock Invoke-Slmgr { [pscustomobject]@{ ExitCode = 0; TimedOut = $false } }

        $r = Restore-LicenseState -BackupPath $good -Force
        $r.Success | Should -BeTrue
        $r.Restored | Should -Contain 'KmsServer'
        Assert-MockCalled Invoke-Slmgr -Times 1 -ParameterFilter { $ArgumentList[0] -eq '/skms' }
    }

    It 'Executa DryRun sem alterar nada' {
        $good = Join-Path $TestDrive 'good2.json'
        $snapshot = [pscustomobject]@{
            BackupTimestamp = '2026-07-30T00:00:00'
            ComputerName   = 'TEST-PC'
            Product        = [pscustomobject]@{ PartialProductKey = 'XXXXX'; Name = 'Windows 10 Pro'; Description = 'RETAIL channel'; LicenseStatus = 1; ID = 'id'; ApplicationId = 'app'; InstallationID = 'inst'; Version = '10.0' }
            Service        = [pscustomobject]@{ KeyManagementServiceMachine = 'kms.antigo'; KeyManagementServicePort = 1688; RemainingWindowsReArmCount = 3 }
            LicenseInfo    = [pscustomobject]@{ Licenca = [pscustomobject]@{ Canal = 'Retail'; Status = 'Licensed'; PartialProductKey = 'XXXXX' } }
            Hardware       = [pscustomobject]@{ HwidAtual = ('a' * 64) }
        }
        $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $good -Encoding UTF8

        Mock Get-SoftwareLicensingProduct { New-CycleProduct -LicenseStatus 1 }
        Mock Get-SoftwareLicensingService { New-CycleService }
        Mock Get-LicenseCycleStatus { [pscustomobject]@{ Channel = 'KMS' } }
        Mock Get-LicenseHardwareContext { [pscustomobject]@{ HwidAtual = ('a' * 64) } }
        Mock Invoke-Slmgr { [pscustomobject]@{ ExitCode = 0; TimedOut = $false } }

        $r = Restore-LicenseState -BackupPath $good -DryRun
        $r.Success | Should -BeTrue
        $r.Message | Should -Match 'DryRun'
        Assert-MockCalled Invoke-Slmgr -Times 0
    }
}

Describe 'ConvertTo-LicenseInfoObject — branches de canal' {
    It 'Mapeia canais nao cobertos pelos testes de ciclo' -TestCases @(
        @{ Desc = 'VOLUME_KMSCLIENT channel'; Esperado = 'KMS' },
        @{ Desc = 'VOLUME_MAK channel'; Esperado = 'MAK' },
        @{ Desc = 'GVLK'; Esperado = 'GVLK' },
        @{ Desc = 'AVMA_EDU'; Esperado = 'AVMA' },
        @{ Desc = 'canal misterioso'; Esperado = 'Desconhecido' }
    ) {
        param($Desc, $Esperado)
        $prod = [pscustomobject]@{
            Name = 'Windows 10 Pro'; Description = $Desc; LicenseStatus = 1
            PartialProductKey = 'XXXXX'; ID = 'id'; InstallationID = 'inst'; Version = '10.0'
        }
        $svc = [pscustomobject]@{ KeyManagementServiceMachine = ''; KeyManagementServicePort = 0; RemainingWindowsReArmCount = 3 }
        $o = ConvertTo-LicenseInfoObject -Product $prod -Service $svc
        $o.Licenca.Canal | Should -Be $Esperado
        $o.Licenca.DigitalLicense | Should -Be ($Esperado -eq 'OEM' -or $Esperado -eq 'Retail')
    }
}

Describe 'Test-LicenseAdminContext' {
    It 'Falha quando a consulta CIM nao retorna dados' {
        Mock Get-CimInstance { @() }
        { Test-LicenseAdminContext } | Should -Throw -ExpectedMessage '*não retornou dados*'
    }

    It 'Falha em contexto nao elevado' {
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Windows' } }
        Mock Test-IsAdministrator { $false }
        { Test-LicenseAdminContext } | Should -Throw -ExpectedMessage '*exige um processo elevado*'
    }
}
