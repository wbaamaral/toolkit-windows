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
}

Describe 'WbaToolkit.Licensing — estrutura BCK-040' {
    It 'Possui manifesto PowerShell 5.1 e dependência Core' {
        $script:manifestContent | Should -Match 'PowerShellVersion\s*=\s*''5\.1'''
        $script:manifestContent | Should -Match 'WbaToolkit\.Core'
    }

    It 'Carrega apenas funções privadas nesta fase' {
        Test-Path (Join-Path $repoRoot 'modules/WbaToolkit.Licensing/WbaToolkit.Licensing.psm1') | Should -BeTrue
        $script:manifestContent | Should -Match 'FunctionsToExport\s*=\s*@\(\)'
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
