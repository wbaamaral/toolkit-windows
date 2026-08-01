#requires -version 5.1

Describe 'gerenciar-drivers - fontes de restauracao' {
    BeforeAll {
        $script:driversScript = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/gerenciar-drivers.ps1'
        $env:WBA_TOOLKIT_TEST_MODE = '1'
        . $script:driversScript
    }

    AfterAll {
        Remove-Item Env:\WBA_TOOLKIT_TEST_MODE -ErrorAction SilentlyContinue
    }

    It 'aceita ZIP com hash SHA256 valido sem acessar o sistema' {
        Mock Test-Path { $true }
        Mock Get-Content { 'A' * 64 }
        Mock Get-FileHashSha256 { 'A' * 64 }

        $result = Test-DriverBackupHash -ZipPath 'C:\entrada\drivers.zip'

        $result.Verified | Should -BeTrue
        $result.Skipped | Should -BeFalse
        Should -Invoke Get-FileHashSha256 -Times 1 -Exactly
    }

    It 'rejeita ZIP com hash invalido antes da extracao' {
        Mock Test-Path { $true }
        Mock Get-Content { 'hash-invalido' }
        Mock Get-FileHashSha256 { throw 'nao deve calcular hash invalido' }

        { Test-DriverBackupHash -ZipPath 'C:\entrada\drivers.zip' } | Should -Throw '*Hash SHA256 invalido*'
        Should -Invoke Get-FileHashSha256 -Times 0 -Exactly
    }

    It 'aceita pasta de backup com metadados sem extrair ZIP' {
        Mock Test-Path { $true }
        Mock Get-Item { [pscustomobject]@{ PSIsContainer = $true; FullName = 'C:\backup\sessao'; Extension = '' } }
        Mock Expand-Archive { throw 'nao deve extrair uma pasta' }

        $result = Resolve-DriverBackupSource -CaminhoBackup 'C:\backup\sessao' -ModulePath 'C:\modulo' -ExtractRoot 'C:\temporario'

        $result.SourceKind | Should -Be 'Pasta'
        $result.SessionPath | Should -Be 'C:\backup\sessao'
        Should -Invoke Expand-Archive -Times 0 -Exactly
    }

    It 'remove uma extracao anterior antes de restaurar um ZIP' {
        Mock Test-Path { $true }
        Mock Get-Item { [pscustomobject]@{ PSIsContainer = $false; FullName = 'C:\entrada\drivers.zip'; Extension = '.zip' } }
        Mock Test-DriverBackupHash { [pscustomobject]@{ Verified = $true } }
        Mock Remove-Item {}
        Mock New-Item { [pscustomobject]@{ FullName = 'C:\temporario' } }
        Mock Expand-Archive {}
        Mock Get-ChildItem { @() }

        $result = Resolve-DriverBackupSource -CaminhoBackup 'C:\entrada\drivers.zip' -ModulePath 'C:\modulo' -ExtractRoot 'C:\temporario'

        $result.SourceKind | Should -Be 'Zip'
        $result.HashChecked | Should -BeTrue
        Should -Invoke Remove-Item -Times 1 -Exactly
        Should -Invoke Expand-Archive -Times 1 -Exactly
    }
}
