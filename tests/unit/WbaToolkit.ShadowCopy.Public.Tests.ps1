#requires -version 5.1

# BCK-070: funcoes publicas do WbaToolkit.ShadowCopy sem teste. CIM, vssadmin, registro e Restauracao do
# Sistema sao simulados; nada cria ou remove copias de sombra.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.ShadowCopy\WbaToolkit.ShadowCopy.psd1') -Force

    function script:New-ScCim {
        param([string]$ClassName, [hashtable]$Properties)
        $obj = [Microsoft.Management.Infrastructure.CimInstance]::new($ClassName, 'root/cimv2')
        foreach ($key in $Properties.Keys) {
            $obj.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create($key, $Properties[$key], [Microsoft.Management.Infrastructure.CimFlags]::None))
        }
        $obj
    }

    $script:idC = '\\?\Volume{c0000000-0000-0000-0000-000000000000}\'
    $script:idD = '\\?\Volume{d0000000-0000-0000-0000-000000000000}\'

    function script:New-ShadowStorageCim {
        param([string]$VolumeId, [string]$DiffId, [uint64]$Used, [uint64]$Allocated, [uint64]$Max)
        New-ScCim 'Win32_ShadowStorage' @{
            Volume         = New-ScCim 'Win32_Volume' @{ DeviceID = $VolumeId }
            DiffVolume     = New-ScCim 'Win32_Volume' @{ DeviceID = $DiffId }
            UsedSpace      = $Used
            AllocatedSpace = $Allocated
            MaxSpace       = $Max
        }
    }
}

Describe 'Funcoes publicas do WbaToolkit.ShadowCopy' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Volume' } {
            New-ScCim 'Win32_Volume' @{ DeviceID = $script:idC; Name = 'C:\' }
            New-ScCim 'Win32_Volume' @{ DeviceID = $script:idD; Name = 'D:\' }
        }
        Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } {
            New-ShadowStorageCim $script:idC $script:idD 1GB 2GB 10GB
            New-ShadowStorageCim $script:idD $script:idD 0 512MB ([uint64]::MaxValue)
        }
        Mock -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin { [pscustomobject]@{ ExitCode = 0; Output = 'ok'; Lines = @('ok') } }
    }

    Context 'Get-ShadowCopyStorage' {
        It 'Le Win32_ShadowStorage com volumes por letra e tamanhos em bytes' {
            $r = @(Get-ShadowCopyStorage)

            $r.Count | Should -Be 2
            $c = $r | Where-Object Volume -eq 'C:\'
            $c.ShadowCopyVolume | Should -Be 'D:\'
            $c.UsedSpaceBytes | Should -Be 1GB
            $c.AllocatedSpaceBytes | Should -Be 2GB
            $c.MaxSpaceBytes | Should -Be 10GB
            $c.MaximumSpace | Should -Be ('{0:N2} GB' -f 10)
            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin -Times 0 -Exactly
        }

        It 'Limite ilimitado vira "Sem limite" e MaxSpaceBytes nulo' {
            $d = Get-ShadowCopyStorage -Volume 'D'

            $d.Volume | Should -Be 'D:\'
            $d.MaximumSpace | Should -Be 'Sem limite'
            $d.MaxSpaceBytes | Should -BeNullOrEmpty
        }

        It 'Filtra pelo volume informado' {
            @(Get-ShadowCopyStorage -Volume 'C:').Volume | Should -Be @('C:\')
            @(Get-ShadowCopyStorage -Volume 'E:').Count | Should -Be 0
        }

        It 'Falha do CIM vira aviso e lista vazia' {
            Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } { throw 'acesso negado' }

            $r = @(Get-ShadowCopyStorage -WarningVariable avisos -WarningAction SilentlyContinue)

            $r.Count | Should -Be 0
            $avisos | Should -Match 'acesso negado'
        }

        It 'Recusa volume invalido' {
            { Get-ShadowCopyStorage -Volume 'nao-e-volume' } | Should -Throw '*Volume invalido*'
        }
    }

    Context 'Get-ShadowCopyProtectionStatus' {
        BeforeEach {
            Mock -ModuleName WbaToolkit.ShadowCopy Get-Volume {
                [pscustomobject]@{ DriveLetter = 'C'; DriveType = 'Fixed'; FileSystemLabel = 'Sistema'; FileSystem = 'NTFS'; Size = 100GB; SizeRemaining = 40GB }
                [pscustomobject]@{ DriveLetter = 'D'; DriveType = 'Fixed'; FileSystemLabel = 'Dados'; FileSystem = 'NTFS'; Size = 200GB; SizeRemaining = 150GB }
                [pscustomobject]@{ DriveLetter = 'E'; DriveType = 'Removable'; FileSystemLabel = 'Pendrive'; FileSystem = 'FAT32'; Size = 8GB; SizeRemaining = 1GB }
                [pscustomobject]@{ DriveLetter = $null; DriveType = 'Fixed'; FileSystemLabel = 'Recovery'; FileSystem = 'NTFS'; Size = 1GB; SizeRemaining = 0 }
            }
            Mock -ModuleName WbaToolkit.ShadowCopy Get-ItemProperty { [pscustomobject]@{ RPSessionInterval = 1; DisableSR = 0 } }
        }

        It 'Lista volumes fixos com letra e o espaco alocado de cada um' {
            $r = @(Get-ShadowCopyProtectionStatus)

            $r.Volume | Should -Be @('C:\', 'D:\')
            $r[0].AllocatedGB | Should -Be 2
            $r[1].AllocatedGB | Should -Be 0.5
            $r[0].SizeGB | Should -Be 100
            $r[0].FreeGB | Should -Be 40
            $r[0].ProtectionEnabled | Should -BeTrue
        }

        It 'Volume sem associacao fica com AllocatedGB nulo' {
            Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } {
                New-ShadowStorageCim $script:idC $script:idC 0 1GB 5GB
            }

            $r = @(Get-ShadowCopyProtectionStatus)
            $r[1].AllocatedGB | Should -BeNullOrEmpty
        }

        It 'DisableSR desliga a protecao' {
            Mock -ModuleName WbaToolkit.ShadowCopy Get-ItemProperty { [pscustomobject]@{ RPSessionInterval = 1; DisableSR = 1 } }

            @(Get-ShadowCopyProtectionStatus)[0].ProtectionEnabled | Should -BeFalse
        }
    }

    Context 'Set-ShadowCopyStorageLimit' {
        It 'Por tamanho: passa /for, /on da associacao e /maxsize em bytes' {
            $out = Set-ShadowCopyStorageLimit -Volume 'C:' -MaxSizeGB 10 -Confirm:$false

            $out | Should -Match 'atualizado'
            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin -Times 1 -Exactly -ParameterFilter {
                ($Arguments -join ' ') -eq 'resize shadowstorage /for=C:\ /on=D:\ /maxsize=10737418240B'
            }
        }

        It 'Por percentual: usa ponto decimal independente da cultura' {
            Set-ShadowCopyStorageLimit -Volume 'D:' -MaxSizePercent 7.5 -Confirm:$false | Out-Null

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin -Times 1 -Exactly -ParameterFilter {
                ($Arguments -join ' ') -eq 'resize shadowstorage /for=D:\ /on=D:\ /maxsize=7.5%'
            }
        }

        It 'Sem associacao usa o proprio volume no /on' {
            Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } { }

            Set-ShadowCopyStorageLimit -Volume 'C' -MaxSizeGB 1 -Confirm:$false | Out-Null

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin -ParameterFilter { $Arguments -contains '/on=C:\' }
        }

        It 'Codigo de saida diferente de zero vira erro' {
            Mock -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin { [pscustomobject]@{ ExitCode = 2; Output = 'Erro: parametro invalido'; Lines = @() } }

            Set-ShadowCopyStorageLimit -Volume 'C:' -MaxSizeGB 10 -Confirm:$false -ErrorVariable erros -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            "$erros" | Should -Match 'parametro invalido'
        }

        It '-WhatIf nao chama o vssadmin' {
            Set-ShadowCopyStorageLimit -Volume 'C:' -MaxSizeGB 10 -WhatIf

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin -Times 0 -Exactly
        }
    }

    Context 'Enable-SystemProtection e Disable-SystemProtection' {
        BeforeEach {
            Mock -ModuleName WbaToolkit.ShadowCopy Enable-ComputerRestore { }
            Mock -ModuleName WbaToolkit.ShadowCopy Disable-ComputerRestore { }
        }

        It 'Enable habilita a protecao no volume' {
            Enable-SystemProtection -Volume 'D' -Confirm:$false | Should -Match 'habilitada em D:\\'

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Enable-ComputerRestore -Times 1 -Exactly -ParameterFilter { $Drive -eq 'D:\' }
            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin -Times 0 -Exactly
        }

        It 'Enable com -MaxAllocationGB aplica o limite pelo resize completo' {
            Enable-SystemProtection -Volume 'C:' -MaxAllocationGB 5 -Confirm:$false | Out-Null

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin -Times 1 -Exactly -ParameterFilter {
                ($Arguments -join ' ') -eq 'resize shadowstorage /for=C:\ /on=D:\ /maxsize=5368709120B'
            }
        }

        It 'Enable avisa quando o limite nao foi aplicado' {
            Mock -ModuleName WbaToolkit.ShadowCopy Invoke-VssAdmin { [pscustomobject]@{ ExitCode = 1; Output = 'falhou'; Lines = @() } }

            Enable-SystemProtection -Volume 'C:' -MaxAllocationGB 5 -Confirm:$false -WarningVariable avisos -WarningAction SilentlyContinue | Out-Null

            $avisos | Should -Match 'nao foi aplicado'
        }

        It 'Enable -WhatIf nao altera nada' {
            Enable-SystemProtection -Volume 'C:' -WhatIf

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Enable-ComputerRestore -Times 0 -Exactly
        }

        It 'Enable com falha vira erro' {
            Mock -ModuleName WbaToolkit.ShadowCopy Enable-ComputerRestore { throw 'servico desativado' }

            Enable-SystemProtection -Volume 'C:' -Confirm:$false -ErrorVariable erros -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            "$erros" | Should -Match 'servico desativado'
        }

        It 'Disable desabilita e avisa sobre a perda das copias' {
            $out = Disable-SystemProtection -Volume 'C:' -Confirm:$false -WarningVariable avisos -WarningAction SilentlyContinue

            $out | Should -Match 'desabilitada em C:\\'
            $avisos | Should -Match 'removidos'
            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Disable-ComputerRestore -Times 1 -Exactly -ParameterFilter { $Drive -eq 'C:\' }
        }

        It 'Disable -WhatIf nao altera nada' {
            Disable-SystemProtection -Volume 'C:' -WhatIf

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Disable-ComputerRestore -Times 0 -Exactly
        }
    }

    Context 'New-ShadowCopy' {
        BeforeEach {
            Mock -ModuleName WbaToolkit.ShadowCopy Start-Sleep { }
            Mock -ModuleName WbaToolkit.ShadowCopy Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; ShadowID = '{NOVA}' } }
            Mock -ModuleName WbaToolkit.ShadowCopy Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ShadowCopy' } {
                New-ScCim 'Win32_ShadowCopy' @{ ID = '{OUTRA}'; DeviceObject = '\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1'; State = 12 }
                New-ScCim 'Win32_ShadowCopy' @{ ID = '{NOVA}'; DeviceObject = '\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy2'; State = 12 }
            }
        }

        It 'Cria a copia pelo Win32_ShadowCopy.Create e devolve os dados dela' {
            $r = New-ShadowCopy -Volume 'C' -Confirm:$false

            $r.ShadowCopyId | Should -Be '{NOVA}'
            $r.Volume | Should -Be 'C:\'
            $r.DeviceObject | Should -Be '\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy2'
            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_ShadowCopy' -and $MethodName -eq 'Create' -and $Arguments.Volume -eq 'C:\'
            }
        }

        It 'ReturnValue diferente de zero vira erro' {
            Mock -ModuleName WbaToolkit.ShadowCopy Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 5; ShadowID = $null } }

            New-ShadowCopy -Volume 'C:' -Confirm:$false -ErrorVariable erros -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            "$erros" | Should -Match 'ReturnValue=5'
        }

        It '-WhatIf nao cria nada' {
            New-ShadowCopy -Volume 'C:' -WhatIf

            Should -Invoke -ModuleName WbaToolkit.ShadowCopy Invoke-CimMethod -Times 0 -Exactly
        }
    }
}
