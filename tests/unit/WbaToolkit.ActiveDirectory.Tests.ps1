#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:launcherContent = Get-XtudoLauncherContent
    $script:adPath = Join-Path (Get-XtudoScriptsRoot) 'diagnosticar-ad-cliente.ps1'
    $script:adContent = Get-Content -LiteralPath $script:adPath -Raw
}

Describe 'Xtudo diagnostico AD do cliente' {
    It 'Mantem o script oficial de AD em scripts/' {
        Test-Path -LiteralPath $script:adPath | Should -BeTrue
        $script:adContent | Should -Match "ValidateSet\('Diagnostico', 'Assistido'\)"
        $script:adContent | Should -Match 'WbaToolkit\.Core\.psd1'
        $script:adContent | Should -Match 'WbaToolkit\.Startup\.psd1'
    }

    It 'Cobre o contrato de diagnóstico do cliente AD' {
        $script:adContent | Should -Match 'Test-ComputerSecureChannel'
        $script:adContent | Should -Match 'Reset-ComputerMachinePassword'
        $script:adContent | Should -Match 'Resolve-DnsName'
        $script:adContent | Should -Match 'SYSVOL'
        $script:adContent | Should -Match 'NETLOGON'
        $script:adContent | Should -Match 'Get-ServiceStartupState'
        $script:adContent | Should -Match 'gpresult'
    }

    It 'Nao referencia experimental no script oficial de AD' {
        $script:adContent | Should -Not -Match 'experimental/'
    }

    It 'Expõe a rota no launcher' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-ad-cliente\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Diagnosticar AD cliente'"
        $script:launcherContent | Should -Match "Keywords\s+=\s+@\('ad', 'active directory', 'gpo', 'secure channel', 'netlogon', 'sysvol', 'ldap', 'dominio'\)"
    }
}
