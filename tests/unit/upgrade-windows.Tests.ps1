#requires -version 5.1
# Projeto: wba-windows-toolkit
# Autor: wbaamaral

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $CorePath = Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
    Import-Module $CorePath -Force -ErrorAction Stop

    $env:WBA_PESTER_TESTING = '1'
    . (Join-Path $repoRoot 'updates/upgrade-windows.ps1')
}

AfterAll {
    Remove-Item env:WBA_PESTER_TESTING -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
Describe 'Assert-UpgradeParameters' {

    Context 'Combinacoes validas' {
        It 'Aceita Backend Auto sem bloqueios' {
            { Assert-UpgradeParameters -Backend 'Auto' } | Should -Not -Throw
        }
        It 'Aceita Backend WinGet sem NoWinGet' {
            { Assert-UpgradeParameters -Backend 'WinGet' } | Should -Not -Throw
        }
        It 'Aceita Backend Chocolatey sem NoChocolatey' {
            { Assert-UpgradeParameters -Backend 'Chocolatey' } | Should -Not -Throw
        }
        It 'Aceita Backend All com apenas NoChocolatey' {
            { Assert-UpgradeParameters -Backend 'All' -NoChocolatey } | Should -Not -Throw
        }
        It 'Aceita Backend All com apenas NoWinGet' {
            { Assert-UpgradeParameters -Backend 'All' -NoWinGet } | Should -Not -Throw
        }
        It 'Aceita Backend Auto com NoWinGet e NoChocolatey (WU continua possivel)' {
            { Assert-UpgradeParameters -Backend 'Auto' -NoWinGet -NoChocolatey } | Should -Not -Throw
        }
    }

    Context 'Combinacoes invalidas' {
        It 'Rejeita Backend WinGet com NoWinGet' {
            { Assert-UpgradeParameters -Backend 'WinGet' -NoWinGet } | Should -Throw
        }
        It 'Rejeita Backend Chocolatey com NoChocolatey' {
            { Assert-UpgradeParameters -Backend 'Chocolatey' -NoChocolatey } | Should -Throw
        }
        It 'Rejeita Backend All com NoWinGet e NoChocolatey e NoWindowsUpdate' {
            { Assert-UpgradeParameters -Backend 'All' -NoWinGet -NoChocolatey -NoWindowsUpdate } | Should -Throw
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Test-BackendAvailable' {

    Context 'WinGet' {
        It 'Retorna true quando winget.exe encontrado' {
            Mock Get-Command { [PSCustomObject]@{ Name = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
            Test-BackendAvailable -Backend 'WinGet' | Should -BeTrue
        }
        It 'Retorna false quando winget.exe ausente' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget.exe' }
            Test-BackendAvailable -Backend 'WinGet' | Should -BeFalse
        }
    }

    Context 'Chocolatey' {
        It 'Retorna true quando choco.exe encontrado' {
            Mock Get-Command { [PSCustomObject]@{ Name = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco.exe' }
            Test-BackendAvailable -Backend 'Chocolatey' | Should -BeTrue
        }
        It 'Retorna false quando choco.exe ausente' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'choco.exe' }
            Test-BackendAvailable -Backend 'Chocolatey' | Should -BeFalse
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Resolve-UpgradeBackend' {

    Context 'Backend Auto — resolucao por disponibilidade' {
        It 'Resolve para WinGet quando WinGet disponivel' {
            Mock Test-BackendAvailable { $true }  -ParameterFilter { $Backend -eq 'WinGet' }
            Mock Test-BackendAvailable { $false } -ParameterFilter { $Backend -eq 'Chocolatey' }
            $r = Resolve-UpgradeBackend -Backend 'Auto'
            $r.Backend | Should -Be 'WinGet'
        }
        It 'Resolve para Chocolatey quando WinGet ausente e Chocolatey disponivel' {
            Mock Test-BackendAvailable { $false } -ParameterFilter { $Backend -eq 'WinGet' }
            Mock Test-BackendAvailable { $true }  -ParameterFilter { $Backend -eq 'Chocolatey' }
            $r = Resolve-UpgradeBackend -Backend 'Auto'
            $r.Backend | Should -Be 'Chocolatey'
        }
        It 'Resolve para None quando nenhum backend disponivel' {
            Mock Test-BackendAvailable { $false }
            $r = Resolve-UpgradeBackend -Backend 'Auto'
            $r.Backend | Should -Be 'None'
        }
        It 'Respeita NoWinGet: ignora WinGet e cai para Chocolatey' {
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'WinGet' }
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'Chocolatey' }
            $r = Resolve-UpgradeBackend -Backend 'Auto' -NoWinGet
            $r.Backend | Should -Be 'Chocolatey'
        }
        It 'Respeita NoChocolatey: ignora Chocolatey e cai para WinGet' {
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'WinGet' }
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'Chocolatey' }
            $r = Resolve-UpgradeBackend -Backend 'Auto' -NoChocolatey
            $r.Backend | Should -Be 'WinGet'
        }
        It 'Retorna motivo da resolucao' {
            Mock Test-BackendAvailable { $true }  -ParameterFilter { $Backend -eq 'WinGet' }
            Mock Test-BackendAvailable { $false } -ParameterFilter { $Backend -eq 'Chocolatey' }
            $r = Resolve-UpgradeBackend -Backend 'Auto'
            $r.Reason | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Backend explicito WinGet' {
        It 'Retorna WinGet quando disponivel' {
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'WinGet' }
            $r = Resolve-UpgradeBackend -Backend 'WinGet'
            $r.Backend | Should -Be 'WinGet'
        }
        It 'Lanca erro quando WinGet solicitado mas ausente' {
            Mock Test-BackendAvailable { $false } -ParameterFilter { $Backend -eq 'WinGet' }
            { Resolve-UpgradeBackend -Backend 'WinGet' } | Should -Throw
        }
    }

    Context 'Backend explicito Chocolatey' {
        It 'Retorna Chocolatey quando disponivel' {
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'Chocolatey' }
            $r = Resolve-UpgradeBackend -Backend 'Chocolatey'
            $r.Backend | Should -Be 'Chocolatey'
        }
        It 'Lanca erro quando Chocolatey solicitado mas ausente' {
            Mock Test-BackendAvailable { $false } -ParameterFilter { $Backend -eq 'Chocolatey' }
            { Resolve-UpgradeBackend -Backend 'Chocolatey' } | Should -Throw
        }
    }

    Context 'Backend All' {
        It 'Retorna All quando ambos disponiveis' {
            Mock Test-BackendAvailable { $true }
            $r = Resolve-UpgradeBackend -Backend 'All'
            $r.Backend | Should -Be 'All'
        }
        It 'Retorna WinGet quando All com NoChocolatey' {
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'WinGet' }
            $r = Resolve-UpgradeBackend -Backend 'All' -NoChocolatey
            $r.Backend | Should -Be 'WinGet'
        }
        It 'Retorna Chocolatey quando All com NoWinGet' {
            Mock Test-BackendAvailable { $true } -ParameterFilter { $Backend -eq 'Chocolatey' }
            $r = Resolve-UpgradeBackend -Backend 'All' -NoWinGet
            $r.Backend | Should -Be 'Chocolatey'
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Test-PendingReboot' {

    Context 'Sem reboot pendente' {
        It 'Retorna false quando nenhuma chave de reboot existe' {
            Mock Test-RegistryPathExists { $false }
            Test-PendingReboot | Should -BeFalse
        }
    }

    Context 'Com reboot pendente' {
        It 'Retorna true quando CBS RebootPending existe' {
            Mock Test-RegistryPathExists { $false }
            Mock Test-RegistryPathExists { $true } -ParameterFilter {
                $Path -like '*Component Based Servicing*RebootPending*'
            }
            Test-PendingReboot | Should -BeTrue
        }
        It 'Retorna true quando WindowsUpdate RebootRequired existe' {
            Mock Test-RegistryPathExists { $false }
            Mock Test-RegistryPathExists { $true } -ParameterFilter {
                $Path -like '*WindowsUpdate*RebootRequired*'
            }
            Test-PendingReboot | Should -BeTrue
        }
        It 'Retorna true quando PendingFileRenameOperations existe' {
            Mock Test-RegistryPathExists { $false }
            Mock Test-RegistryPathExists { $true } -ParameterFilter {
                $Path -like '*PendingFileRenameOperations*'
            }
            Test-PendingReboot | Should -BeTrue
        }
        It 'Retorna boolean (nao nulo)' {
            Mock Test-RegistryPathExists { $false }
            $result = Test-PendingReboot
            $result | Should -BeOfType [bool]
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-UpgradeExitCode' {

    It 'Retorna 0 quando sucesso sem reboot pendente' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $true -BackendPartialFailure $false `
            -WUSuccess $true -WUSkipped $false `
            -RebootPending $false `
            -ParameterError $false -BackendUnavailable $false `
            -Cancelled $false
        $r | Should -Be 0
    }
    It 'Retorna 7 quando sucesso com reboot pendente' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $true -BackendPartialFailure $false `
            -WUSuccess $true -WUSkipped $false `
            -RebootPending $true `
            -ParameterError $false -BackendUnavailable $false `
            -Cancelled $false
        $r | Should -Be 7
    }
    It 'Retorna 4 quando falha parcial no backend' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $false -BackendPartialFailure $true `
            -WUSuccess $true -WUSkipped $false `
            -RebootPending $false `
            -ParameterError $false -BackendUnavailable $false `
            -Cancelled $false
        $r | Should -Be 4
    }
    It 'Retorna 5 quando falha total no backend' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $false -BackendPartialFailure $false `
            -WUSuccess $true -WUSkipped $false `
            -RebootPending $false `
            -ParameterError $false -BackendUnavailable $false `
            -Cancelled $false
        $r | Should -Be 5
    }
    It 'Retorna 6 quando falha no Windows Update' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $true -BackendPartialFailure $false `
            -WUSuccess $false -WUSkipped $false `
            -RebootPending $false `
            -ParameterError $false -BackendUnavailable $false `
            -Cancelled $false
        $r | Should -Be 6
    }
    It 'Retorna 8 quando erro de parametro' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $false -BackendPartialFailure $false `
            -WUSuccess $false -WUSkipped $false `
            -RebootPending $false `
            -ParameterError $true -BackendUnavailable $false `
            -Cancelled $false
        $r | Should -Be 8
    }
    It 'Retorna 9 quando cancelado pelo operador' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $false -BackendPartialFailure $false `
            -WUSuccess $false -WUSkipped $false `
            -RebootPending $false `
            -ParameterError $false -BackendUnavailable $false `
            -Cancelled $true
        $r | Should -Be 9
    }
    It 'Retorna 2 quando backend solicitado nao disponivel' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $false -BackendPartialFailure $false `
            -WUSuccess $false -WUSkipped $false `
            -RebootPending $false `
            -ParameterError $false -BackendUnavailable $true `
            -Cancelled $false
        $r | Should -Be 2
    }
    It 'Falha parcial com reboot pendente retorna 4 (pior estado prevalece)' {
        $r = Get-UpgradeExitCode `
            -BackendSuccess $false -BackendPartialFailure $true `
            -WUSuccess $true -WUSkipped $false `
            -RebootPending $true `
            -ParameterError $false -BackendUnavailable $false `
            -Cancelled $false
        $r | Should -Be 4
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-ListOnly' {

    BeforeEach {
        Mock Invoke-WinGetUpgrade { }
        Mock Invoke-ChocolateyUpgrade { }
        Mock Invoke-WindowsUpdateStep { }
        Mock Invoke-WinGetList { @() }
        Mock Invoke-ChocolateyList { @() }
    }

    It 'Nao chama Invoke-WinGetUpgrade em ListOnly com WinGet' {
        Invoke-ListOnly -ResolvedBackend 'WinGet'
        Should -Invoke Invoke-WinGetUpgrade -Times 0
    }
    It 'Nao chama Invoke-ChocolateyUpgrade em ListOnly com Chocolatey' {
        Invoke-ListOnly -ResolvedBackend 'Chocolatey'
        Should -Invoke Invoke-ChocolateyUpgrade -Times 0
    }
    It 'Nao executa Windows Update em ListOnly com WinGet' {
        Invoke-ListOnly -ResolvedBackend 'WinGet'
        Should -Invoke Invoke-WindowsUpdateStep -Times 0
    }
    It 'Nao executa Windows Update em ListOnly com Chocolatey' {
        Invoke-ListOnly -ResolvedBackend 'Chocolatey'
        Should -Invoke Invoke-WindowsUpdateStep -Times 0
    }
    It 'Chama Invoke-WinGetList para backend WinGet' {
        Invoke-ListOnly -ResolvedBackend 'WinGet'
        Should -Invoke Invoke-WinGetList -Times 1
    }
    It 'Chama Invoke-ChocolateyList para backend Chocolatey' {
        Invoke-ListOnly -ResolvedBackend 'Chocolatey'
        Should -Invoke Invoke-ChocolateyList -Times 1
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-UpgradeAll' {

    BeforeEach {
        Mock Invoke-WinGetUpgrade { [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }
        Mock Invoke-ChocolateyUpgrade { [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }
        Mock Invoke-WindowsUpdateStep { [PSCustomObject]@{ Success = $true; Skipped = $false; ExitCode = 0 } }
        Mock Test-PendingReboot { $false }
    }

    Context 'Ordem de execucao — backend antes do Windows Update' {
        It 'Executa WinGet antes do Windows Update' {
            $order = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-WinGetUpgrade     { $order.Add('WinGet'); [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }
            Mock Invoke-WindowsUpdateStep { $order.Add('WU');     [PSCustomObject]@{ Success = $true; Skipped = $false; ExitCode = 0 } }

            Invoke-UpgradeAll -ResolvedBackend 'WinGet'

            $order[0] | Should -Be 'WinGet'
            $order[1] | Should -Be 'WU'
        }
        It 'Executa Chocolatey antes do Windows Update' {
            $order = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ChocolateyUpgrade { $order.Add('Chocolatey'); [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }
            Mock Invoke-WindowsUpdateStep { $order.Add('WU');         [PSCustomObject]@{ Success = $true; Skipped = $false; ExitCode = 0 } }

            Invoke-UpgradeAll -ResolvedBackend 'Chocolatey'

            $order[0] | Should -Be 'Chocolatey'
            $order[1] | Should -Be 'WU'
        }
    }

    Context 'Backend All — sequencia WinGet depois Chocolatey' {
        It 'Executa WinGet antes de Chocolatey' {
            $order = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-WinGetUpgrade     { $order.Add('WinGet');     [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }
            Mock Invoke-ChocolateyUpgrade { $order.Add('Chocolatey'); [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }

            Invoke-UpgradeAll -ResolvedBackend 'All' -NoWindowsUpdate

            $order[0] | Should -Be 'WinGet'
            $order[1] | Should -Be 'Chocolatey'
        }
        It 'Nao executa backends em paralelo (concluiu ambos em sequencia)' {
            $order = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-WinGetUpgrade     { $order.Add('WinGet');     [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }
            Mock Invoke-ChocolateyUpgrade { $order.Add('Chocolatey'); [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 } }

            Invoke-UpgradeAll -ResolvedBackend 'All' -NoWindowsUpdate

            $order.Count | Should -Be 2
        }
    }

    Context 'NoWindowsUpdate' {
        It 'Nao executa Windows Update quando NoWindowsUpdate informado' {
            Invoke-UpgradeAll -ResolvedBackend 'WinGet' -NoWindowsUpdate
            Should -Invoke Invoke-WindowsUpdateStep -Times 0
        }
        It 'Executa Windows Update quando NoWindowsUpdate nao informado' {
            Invoke-UpgradeAll -ResolvedBackend 'WinGet'
            Should -Invoke Invoke-WindowsUpdateStep -Times 1
        }
    }

    Context 'Nenhum backend disponivel (None)' {
        It 'Executa apenas Windows Update quando backend None e WU habilitado' {
            Invoke-UpgradeAll -ResolvedBackend 'None'
            Should -Invoke Invoke-WinGetUpgrade -Times 0
            Should -Invoke Invoke-ChocolateyUpgrade -Times 0
            Should -Invoke Invoke-WindowsUpdateStep -Times 1
        }
        It 'Lanca erro quando backend None e NoWindowsUpdate' {
            { Invoke-UpgradeAll -ResolvedBackend 'None' -NoWindowsUpdate } | Should -Throw
        }
    }

    Context 'Verificacao de reboot pendente' {
        It 'Verifica reboot pendente antes e depois da execucao' {
            $callCount = 0
            Mock Test-PendingReboot { $callCount++; $false }

            Invoke-UpgradeAll -ResolvedBackend 'WinGet' -NoWindowsUpdate

            $callCount | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Retorna resultado consolidado' {
        It 'Retorna objeto com propriedade BackendResult' {
            $r = Invoke-UpgradeAll -ResolvedBackend 'WinGet' -NoWindowsUpdate
            $r.PSObject.Properties.Name | Should -Contain 'BackendResult'
        }
        It 'Retorna objeto com propriedade RebootPendingAfter' {
            $r = Invoke-UpgradeAll -ResolvedBackend 'WinGet' -NoWindowsUpdate
            $r.PSObject.Properties.Name | Should -Contain 'RebootPendingAfter'
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-SelectUpgrade' {

    BeforeEach {
        Mock Invoke-WinGetList { @(
            [PSCustomObject]@{ Id = 'Git.Git'; Name = 'Git'; CurrentVersion = '2.44'; AvailableVersion = '2.45' }
        ) }
        Mock Invoke-ChocolateyList { @(
            [PSCustomObject]@{ Id = 'git'; Name = 'git'; CurrentVersion = '2.44'; AvailableVersion = '2.45' }
        ) }
        Mock Invoke-WinGetUpgradePackage { }
        Mock Invoke-ChocolateyUpgradePackage { }
        Mock Invoke-WindowsUpdateStep { }
        Mock Read-PackageSelection { @() }
    }

    It 'Nao executa Windows Update automaticamente em Select com WinGet' {
        Invoke-SelectUpgrade -ResolvedBackend 'WinGet'
        Should -Invoke Invoke-WindowsUpdateStep -Times 0
    }
    It 'Nao executa Windows Update automaticamente em Select com Chocolatey' {
        Invoke-SelectUpgrade -ResolvedBackend 'Chocolatey'
        Should -Invoke Invoke-WindowsUpdateStep -Times 0
    }
    It 'Nao executa upgrade quando operador cancela selecao' {
        Mock Read-PackageSelection { @() }
        Invoke-SelectUpgrade -ResolvedBackend 'WinGet'
        Should -Invoke Invoke-WinGetUpgradePackage -Times 0
    }
    It 'Executa upgrade apenas dos pacotes selecionados' {
        Mock Read-PackageSelection { @('Git.Git') }
        Mock Invoke-WinGetUpgradePackage { } -ParameterFilter { $PackageId -eq 'Git.Git' }
        Invoke-SelectUpgrade -ResolvedBackend 'WinGet'
        Should -Invoke Invoke-WinGetUpgradePackage -Times 1
    }
}

# ---------------------------------------------------------------------------
Describe 'Show-UpgradeSummary' {

    It 'Nao lanca excecao com resumo minimo valido' {
        $summary = [PSCustomObject]@{
            Backend        = 'WinGet'
            Action         = 'UpgradeAll'
            NoWindowsUpdate = $false
            BackendResult  = [PSCustomObject]@{ Success = $true; Partial = $false; ExitCode = 0 }
            WUResult       = [PSCustomObject]@{ Success = $true; Skipped = $false; ExitCode = 0 }
            RebootPendingBefore = $false
            RebootPendingAfter  = $false
            ExitCode       = 0
        }
        { Show-UpgradeSummary -Summary $summary } | Should -Not -Throw
    }
}
