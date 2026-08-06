#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot = Get-XtudoRepoRoot
    $script:corePsd1 = Join-Path $script:repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
    $script:psd1     = Join-Path $script:repoRoot 'modules/WbaToolkit.Provisioning/WbaToolkit.Provisioning.psd1'

    Import-Module $script:corePsd1 -Force -ErrorAction Stop
    Import-Module $script:psd1     -Force -ErrorAction Stop

    # Ver WbaToolkit.Provisioning.Fase2.Tests.ps1 para a explicacao do stub global:
    # InModuleScope isola cada bloco em uma nova child scope, entao uma funcao definida
    # dentro de um InModuleScope some ao terminar aquele bloco; um stub GLOBAL e visivel
    # (e mockavel) de qualquer InModuleScope subsequente.
    $windowsOnlyCommands = @(
        'Get-Disk', 'Get-Partition', 'Get-Volume', 'Initialize-Disk', 'New-Partition',
        'Format-Volume',
        'Get-LocalUser', 'Get-LocalGroup', 'Get-LocalGroupMember', 'New-LocalUser',
        'Add-LocalGroupMember', 'Remove-LocalUser',
        'Get-CimInstance', 'Invoke-CimMethod'
    )
    foreach ($cmd in $windowsOnlyCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            New-Item -Path "function:global:$cmd" -Value {} -Force | Out-Null
        }
    }
}

Describe 'Resolve-ToolkitDisk' {
    It 'Resolve por serialNumber' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @(
                [pscustomobject]@{ Number = 0; SerialNumber = ''; IsSystem = $true; IsBoot = $true; BusType = 'SCSI'; Location = 'L0'; Size = 100GB; UniqueId = 'A' }
                [pscustomobject]@{ Number = 1; SerialNumber = 'SN-XYZ'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B' }
            ) }
            $result = Resolve-ToolkitDisk -Match ([pscustomobject]@{ serialNumber = 'SN-XYZ' })
            $result.Found | Should -BeTrue
            $result.Disk.Number | Should -Be 1
        }
    }

    It 'Resolve por uniqueId' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 1; SerialNumber = ''; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B' }) }
            $result = Resolve-ToolkitDisk -Match ([pscustomobject]@{ uniqueId = 'B' })
            $result.Found | Should -BeTrue
        }
    }

    It 'Resolve por busType+location+sizeBytes com tolerancia' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 1; SerialNumber = ''; IsSystem = $false; IsBoot = $false; BusType = 'SAS'; Location = 'PCI Slot 11'; Size = 49392123904; UniqueId = 'drive-scsi0' }) }
            $result = Resolve-ToolkitDisk -Match ([pscustomobject]@{ busType = 'SAS'; location = 'PCI Slot 11'; sizeBytes = 49392000000; sizeToleranceBytes = 200000 })
            $result.Found | Should -BeTrue
        }
    }

    It 'Recusa o disco de sistema mesmo quando o criterio o alcança' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 0; SerialNumber = 'SN-SYS'; IsSystem = $true; IsBoot = $true; BusType = 'SCSI'; Location = 'L0'; Size = 100GB; UniqueId = 'A' }) }
            $result = Resolve-ToolkitDisk -Match ([pscustomobject]@{ serialNumber = 'SN-SYS' })
            $result.Found | Should -BeFalse
            $result.Message | Should -Match 'sistema'
        }
    }

    It 'Falha por ambiguidade com multiplos candidatos' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @(
                [pscustomobject]@{ Number = 1; SerialNumber = 'DUP'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B' }
                [pscustomobject]@{ Number = 2; SerialNumber = 'DUP'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L2'; Size = 46GB; UniqueId = 'C' }
            ) }
            $result = Resolve-ToolkitDisk -Match ([pscustomobject]@{ serialNumber = 'DUP' })
            $result.Found | Should -BeFalse
            $result.Message | Should -Match 'ambigua'
        }
    }

    It 'Falha sem identificador forte' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @() }
            $result = Resolve-ToolkitDisk -Match ([pscustomobject]@{})
            $result.Found | Should -BeFalse
        }
    }
}

Describe 'Etapa storage.configure' {
    It 'Skipped quando storage.disks nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitStorageDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Failed quando a identificacao do disco e ambigua' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @(
                [pscustomobject]@{ Number = 1; SerialNumber = 'DUP'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B' }
                [pscustomobject]@{ Number = 2; SerialNumber = 'DUP'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L2'; Size = 46GB; UniqueId = 'C' }
            ) }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; storage = @{ disks = @(@{ name = 'd1'; match = @{ serialNumber = 'DUP' } }) } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitStorageDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Failed'
        }
    }

    It 'Changed quando o disco esta RAW' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 1; SerialNumber = 'SN1'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B'; PartitionStyle = 'RAW' }) }
            Mock Get-Partition { }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; storage = @{ disks = @(@{ name = 'd1'; match = @{ serialNumber = 'SN1' } }) } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitStorageDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Changed'
        }
    }

    It 'Compliant quando ja particionado e formatado conforme desejado' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 1; SerialNumber = 'SN1'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B'; PartitionStyle = 'GPT' }) }
            Mock Get-Partition { [pscustomobject]@{ DriveLetter = 'D'; Type = 'Basic' } }
            Mock Get-Volume { [pscustomobject]@{ FileSystem = 'NTFS' } }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; storage = @{ disks = @(@{ name = 'd1'; match = @{ serialNumber = 'SN1' }; driveLetter = 'D'; fileSystem = 'NTFS' }) } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitStorageDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Compliant'
        }
    }

    It 'Set recusa sem policy.allowDestructiveStorage=true' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; storage = @{ disks = @(@{ name = 'd1'; match = @{ serialNumber = 'SN1' } }) } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitStorageDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false } | Should -Throw '*allowDestructiveStorage*'
        }
    }

    It 'Set inicializa, particiona e formata quando autorizado' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 1; SerialNumber = 'SN1'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B'; PartitionStyle = 'RAW' }) }
            Mock Get-Partition { }
            Mock Get-Volume { }
            Mock Initialize-Disk { } -Verifiable
            Mock New-Partition { [pscustomobject]@{ DriveLetter = 'D' } } -Verifiable
            Mock Format-Volume { } -Verifiable

            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                storage       = @{ disks = @(@{ name = 'd1'; match = @{ serialNumber = 'SN1' }; driveLetter = 'D'; fileSystem = 'NTFS' }) }
                policy        = @{ allowDestructiveStorage = $true }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

            Set-ToolkitStorageDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }

    It 'Set recusa mesmo autorizado se o disco resolver para o sistema' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 0; SerialNumber = 'SN-SYS'; IsSystem = $true; IsBoot = $true; BusType = 'SCSI'; Location = 'L0'; Size = 100GB; UniqueId = 'A' }) }
            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                storage       = @{ disks = @(@{ name = 'd1'; match = @{ serialNumber = 'SN-SYS' } }) }
                policy        = @{ allowDestructiveStorage = $true }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitStorageDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false } | Should -Throw '*'
        }
    }

    It 'Set nao toca em nenhum disco do conjunto quando um deles e ambiguo (atomicidade)' {
        InModuleScope WbaToolkit.Provisioning {
            # d1 (SN1) resolve limpo; d2 (DUP) tem dois candidatos duplicados -> ambiguo.
            # d1 aparece primeiro na lista para provar que resolver-e-formatar d1 antes de
            # falhar em d2 nao acontece mais (ver Set-ToolkitStorageDesiredState.ps1).
            Mock Get-Disk { @(
                [pscustomobject]@{ Number = 1; SerialNumber = 'SN1'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B'; PartitionStyle = 'RAW' }
                [pscustomobject]@{ Number = 2; SerialNumber = 'DUP'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L2'; Size = 46GB; UniqueId = 'C' }
                [pscustomobject]@{ Number = 3; SerialNumber = 'DUP'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L3'; Size = 46GB; UniqueId = 'D' }
            ) }
            Mock Initialize-Disk { } -Verifiable
            Mock New-Partition { [pscustomobject]@{ DriveLetter = 'D' } } -Verifiable
            Mock Format-Volume { } -Verifiable

            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                storage       = @{ disks = @(
                    @{ name = 'd1'; match = @{ serialNumber = 'SN1' }; driveLetter = 'D'; fileSystem = 'NTFS' }
                    @{ name = 'd2'; match = @{ serialNumber = 'DUP' } }
                ) }
                policy        = @{ allowDestructiveStorage = $true }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

            { Set-ToolkitStorageDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false } | Should -Throw '*ambigua*'
            Should -Invoke Initialize-Disk -Times 0
            Should -Invoke New-Partition -Times 0
            Should -Invoke Format-Volume -Times 0
        }
    }

    It 'Set e idempotente: chamar duas vezes em disco ja conforme nao reformata' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-Disk { @([pscustomobject]@{ Number = 1; SerialNumber = 'SN1'; IsSystem = $false; IsBoot = $false; BusType = 'SCSI'; Location = 'L1'; Size = 28GB; UniqueId = 'B'; PartitionStyle = 'GPT' }) }
            Mock Get-Partition { [pscustomobject]@{ DriveLetter = 'D'; Type = 'Basic'; Size = 28GB } }
            Mock Get-Volume { [pscustomobject]@{ FileSystem = 'NTFS'; FileSystemLabel = 'd1' } }
            Mock Initialize-Disk { }
            Mock New-Partition { }
            Mock Format-Volume { }

            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                storage       = @{ disks = @(@{ name = 'd1'; match = @{ serialNumber = 'SN1' }; driveLetter = 'D'; fileSystem = 'NTFS' }) }
                policy        = @{ allowDestructiveStorage = $true }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $context = [pscustomobject]@{ Config = $config }

            Set-ToolkitStorageDesiredState -Context $context -Confirm:$false | Out-Null
            Set-ToolkitStorageDesiredState -Context $context -Confirm:$false | Out-Null

            Should -Invoke Initialize-Disk -Times 0
            Should -Invoke New-Partition -Times 0
            Should -Invoke Format-Volume -Times 0
        }
    }
}

Describe 'Resolve-ToolkitLocalGroup' {
    It 'Resolve grupo bem-conhecido por SID' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Administradores'; SID = 'S-1-5-32-544' } }
            $group = Resolve-ToolkitLocalGroup -Name 'Administrators'
            $group.Name | Should -Be 'Administradores'
        }
    }

    It 'Cai para nome literal quando nao e um grupo bem-conhecido' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-LocalGroup { [pscustomobject]@{ Name = 'GrupoCustom' } } -ParameterFilter { $Name -eq 'GrupoCustom' }
            $group = Resolve-ToolkitLocalGroup -Name 'GrupoCustom'
            $group.Name | Should -Be 'GrupoCustom'
        }
    }
}

Describe 'Etapa accounts.local' {
    It 'Skipped quando accounts nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitAccountsDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Changed quando a conta declarada nao existe' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-LocalUser { $null }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'wbaadmin'; password = @{ secretRef = 'ref1' }; groups = @('Administrators') }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitAccountsDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Changed'
        }
    }

    It 'Compliant quando a conta existe e os grupos ja batem' {
        InModuleScope WbaToolkit.Provisioning {
            $sid = 'S-1-5-21-1-2-3-1001'
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'wbaadmin'; SID = $sid } }
            Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Administradores'; SID = 'S-1-5-32-544' } }
            Mock Get-LocalGroupMember { @([pscustomobject]@{ SID = $sid }) }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'wbaadmin'; groups = @('Administrators') }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitAccountsDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Compliant'
        }
    }

    It 'Set recusa criar conta sem password.secretRef' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-LocalUser { $null }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'semref' }) } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitAccountsDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false } | Should -Throw '*secretRef*'
        }
    }

    It 'Set cria a conta com senha resolvida via secretRef' {
        InModuleScope WbaToolkit.Provisioning {
            $script:getLocalUserCalls = 0
            Mock Get-LocalUser {
                $script:getLocalUserCalls++
                if ($script:getLocalUserCalls -eq 1) { $null } else { [pscustomobject]@{ Name = 'novaconta'; SID = 'S-1-5-21-1-2-3-1002' } }
            }
            Mock Resolve-ToolkitProvisioningSecret { ConvertTo-SecureString 'x' -AsPlainText -Force }
            Mock New-LocalUser { } -Verifiable

            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'novaconta'; password = @{ secretRef = 'ref1' } }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            Set-ToolkitAccountsDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }

    It 'Set recusa remover conta built-in (RID 500)' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; SID = [pscustomobject]@{ Value = 'S-1-5-21-1-2-3-500' } } }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'Administrator'; ensure = 'Absent' }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitAccountsDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false } | Should -Throw '*built-in*'
        }
    }

    It 'Set recusa criar conta quando o secretRef resolve para senha vazia' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-LocalUser { $null }
            Mock Resolve-ToolkitProvisioningSecret { New-Object System.Security.SecureString }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'semref'; password = @{ secretRef = 'ref-vazio' } }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitAccountsDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false } | Should -Throw '*vazia*'
        }
    }

    It 'Set nunca expoe a senha resolvida no resultado (varredura de segredos)' {
        InModuleScope WbaToolkit.Provisioning {
            $script:getLocalUserCalls = 0
            Mock Get-LocalUser {
                $script:getLocalUserCalls++
                if ($script:getLocalUserCalls -eq 1) { $null } else { [pscustomobject]@{ Name = 'novaconta'; SID = 'S-1-5-21-1-2-3-1002' } }
            }
            Mock Resolve-ToolkitProvisioningSecret { ConvertTo-SecureString 'SENHA-SECRETA-XYZ' -AsPlainText -Force }
            Mock New-LocalUser { }

            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'novaconta'; password = @{ secretRef = 'ref1' } }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $result = Set-ToolkitAccountsDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false
            ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'SENHA-SECRETA-XYZ'
        }
    }

    It 'Set e idempotente: chamar duas vezes em conta ja conforme nao recria nem reaplica grupo' {
        InModuleScope WbaToolkit.Provisioning {
            $sid = 'S-1-5-21-1-2-3-1003'
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'jaexiste'; SID = $sid } }
            Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Administradores'; SID = 'S-1-5-32-544' } }
            Mock Get-LocalGroupMember { @([pscustomobject]@{ SID = $sid }) }
            Mock New-LocalUser { }
            Mock Add-LocalGroupMember { }

            $config = @{ schemaVersion = 1; deploymentId = 'x'; accounts = @(@{ name = 'jaexiste'; groups = @('Administrators') }) } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $context = [pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }

            Set-ToolkitAccountsDesiredState -Context $context -Confirm:$false | Out-Null
            Set-ToolkitAccountsDesiredState -Context $context -Confirm:$false | Out-Null

            Should -Invoke New-LocalUser -Times 0
            Should -Invoke Add-LocalGroupMember -Times 0
        }
    }
}

Describe 'Etapa activation.apply' {
    It 'Skipped quando activation nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitActivationDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Compliant quando o partialProductKey ja bate' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-CimInstance { @([pscustomobject]@{ PartialProductKey = 'ABCDE' }) }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; activation = @{ productKeySecretRef = 'ref1'; partialProductKey = 'ABCDE' } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitActivationDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Compliant'
        }
    }

    It 'Changed quando o partialProductKey diverge' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-CimInstance { @([pscustomobject]@{ PartialProductKey = 'ZZZZZ' }) }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; activation = @{ productKeySecretRef = 'ref1'; partialProductKey = 'ABCDE' } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitActivationDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Changed'
        }
    }

    It 'Set recusa sem productKeySecretRef' {
        InModuleScope WbaToolkit.Provisioning {
            $config = @{ schemaVersion = 1; deploymentId = 'x'; activation = @{ partialProductKey = 'ABCDE' } } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitActivationDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false } | Should -Throw '*productKeySecretRef*'
        }
    }

    It 'Set cancela sob -WhatIf antes de resolver o segredo' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Resolve-ToolkitProvisioningSecret { throw 'Nao deveria ser chamado sob WhatIf' }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; activation = @{ productKeySecretRef = 'ref1'; partialProductKey = 'ABCDE' } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitActivationDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -WhatIf } | Should -Not -Throw
        }
    }

    It 'Set instala a chave via SoftwareLicensingService::InstallProductKey, nunca via processo externo' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Resolve-ToolkitProvisioningSecret { ConvertTo-SecureString 'FAKE-KEY-12345' -AsPlainText -Force }
            # Sem -ParameterFilter: o stub global de Invoke-CimMethod (necessario fora do
            # Windows) nao declara parametros, entao Pester nao tem metadado para vincular
            # -ClassName/-MethodName a variaveis no filtro — o filtro nunca bateria.
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0 } } -Verifiable

            $config = @{ schemaVersion = 1; deploymentId = 'x'; activation = @{ productKeySecretRef = 'ref1'; partialProductKey = 'ABCDE' } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $result = Set-ToolkitActivationDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false
            Should -InvokeVerifiable
            $result.Evidence.ReturnValue | Should -Be 0
        }
    }

    It 'Set lanca erro quando InstallProductKey retorna codigo diferente de zero' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Resolve-ToolkitProvisioningSecret { ConvertTo-SecureString 'FAKE-KEY-12345' -AsPlainText -Force }
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 1 } }

            $config = @{ schemaVersion = 1; deploymentId = 'x'; activation = @{ productKeySecretRef = 'ref1'; partialProductKey = 'ABCDE' } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitActivationDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false } | Should -Throw '*1*'
        }
    }

    It 'Set nunca expoe a chave resolvida no resultado (varredura de segredos)' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Resolve-ToolkitProvisioningSecret { ConvertTo-SecureString 'CHAVE-SECRETA-99999' -AsPlainText -Force }
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0 } }

            $config = @{ schemaVersion = 1; deploymentId = 'x'; activation = @{ productKeySecretRef = 'ref1'; partialProductKey = 'ABCDE' } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $result = Set-ToolkitActivationDesiredState -Context ([pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Secrets = $TestDrive } }) -Confirm:$false
            ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'CHAVE-SECRETA-99999'
        }
    }
}
