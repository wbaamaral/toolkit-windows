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
            Get-Command Backup-DefaultUserHive    -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Invoke-RegFileImport      -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
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
}
