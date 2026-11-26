#requires -version 5.1

# BCK-065/A-VSS-1: Win32_ShadowCopy identifica o volume por VolumeName (\?\Volume{guid}\).

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.ShadowCopy\WbaToolkit.ShadowCopy.psd1') -Force

    # CimInstance real: Remove-CimInstance recebe pelo pipeline um parametro tipado como CimInstance.
    function global:New-TestCimInstance {
        param([string]$ClassName, [hashtable]$Properties)
        $obj = [Microsoft.Management.Infrastructure.CimInstance]::new($ClassName, 'root/cimv2')
        foreach ($key in $Properties.Keys) {
            $obj.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create($key, $Properties[$key], [Microsoft.Management.Infrastructure.CimFlags]::None))
        }
        $obj
    }
}

AfterAll {
    Remove-Item -Path Function:\New-TestCimInstance -ErrorAction Ignore
}

Describe 'Get-ShadowCopy / Remove-ShadowCopy por volume' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Volume' } {
            New-TestCimInstance 'Win32_Volume' @{ DeviceID = '\?\Volume{c0000000-0000-0000-0000-000000000000}\'; Name = 'C:\' }
            New-TestCimInstance 'Win32_Volume' @{ DeviceID = '\?\Volume{d0000000-0000-0000-0000-000000000000}\'; Name = 'D:\' }
        }
        Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ShadowCopy' } {
            New-TestCimInstance 'Win32_ShadowCopy' @{ ID = '{S1}'; VolumeName = '\?\Volume{c0000000-0000-0000-0000-000000000000}\' }
            New-TestCimInstance 'Win32_ShadowCopy' @{ ID = '{S2}'; VolumeName = '\?\Volume{d0000000-0000-0000-0000-000000000000}\' }
            New-TestCimInstance 'Win32_ShadowCopy' @{ ID = '{S3}'; VolumeName = '\?\Volume{c0000000-0000-0000-0000-000000000000}\' }
        }
        Mock -ModuleName WbaToolkit.ShadowCopy Remove-CimInstance { }
    }

    It 'Get-ShadowCopy -Volume C: devolve so as copias do volume C' {
        $result = @(Get-ShadowCopy -Volume 'C:')

        $result.Count | Should -Be 2
        ($result.ShadowCopyId | Sort-Object) -join ',' | Should -Be '{S1},{S3}'
        $result[0].Volume | Should -Be 'C:\'
    }

    It 'Remove-ShadowCopy -Volume D: remove so a copia do volume D' {
        $out = Remove-ShadowCopy -Volume 'D:' -Confirm:$false

        $out | Should -Be '1 shadow copy(s) removido(s) de D:\.'
        Should -Invoke -ModuleName WbaToolkit.ShadowCopy Remove-CimInstance -Times 1 -Exactly -ParameterFilter { $InputObject.CimInstanceProperties['ID'].Value -eq '{S2}' }
    }

    It 'Remove-ShadowCopy -Volume E: sem copias nao remove nada' {
        Remove-ShadowCopy -Volume 'E:' -Confirm:$false -WarningAction SilentlyContinue | Out-Null

        Should -Invoke -ModuleName WbaToolkit.ShadowCopy Remove-CimInstance -Times 0 -Exactly
    }
}
