#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot = Get-XtudoRepoRoot
    $script:corePsd1 = Join-Path $script:repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
    $script:psd1     = Join-Path $script:repoRoot 'modules/WbaToolkit.Provisioning/WbaToolkit.Provisioning.psd1'

    Import-Module $script:corePsd1 -Force -ErrorAction Stop
    Import-Module $script:psd1     -Force -ErrorAction Stop

    # Cmdlets exclusivos de modulos Windows (NetAdapter, NetSecurity, NetTCPIP, PKI,
    # WSMan) nao existem no pwsh multiplataforma usado para desenvolvimento. Sem um
    # stub previo, Mock nao consegue anexar a um comando que nao existe. Em Windows
    # real esses cmdlets ja existem e o stub nunca e definido.
    $windowsOnlyCommands = @(
        'Get-NetAdapter', 'Get-NetIPInterface', 'Get-NetIPAddress', 'Get-NetRoute',
        'Get-DnsClientServerAddress', 'New-NetIPAddress', 'Remove-NetIPAddress',
        'Set-NetIPInterface', 'Set-DnsClientServerAddress',
        'Get-NetFirewallRule', 'New-NetFirewallRule', 'Set-NetFirewallRule',
        'Enable-NetFirewallRule', 'Disable-NetFirewallRule',
        'Get-NetFirewallProfile', 'Get-NetFirewallPortFilter',
        'Import-Certificate', 'Import-PfxCertificate',
        'Get-WSManInstance', 'New-WSManInstance', 'Remove-WSManInstance',
        'Unprotect-CmsMessage'
    )
    # Stub global (nao no scopo do modulo): InModuleScope isola cada bloco em uma nova
    # child scope via '&', entao uma funcao definida dentro de um InModuleScope some ao
    # terminar aquele bloco. Resolucao de comando, porem, sobe até o scopo global —
    # um stub global e visivel (e mockavel) de qualquer InModuleScope subsequente.
    foreach ($cmd in $windowsOnlyCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            New-Item -Path "function:global:$cmd" -Value {} -Force | Out-Null
        }
    }
}

Describe 'ConvertTo-ToolkitNormalizedMacAddress' {
    It 'Normaliza separadores e caixa' {
        InModuleScope WbaToolkit.Provisioning {
            ConvertTo-ToolkitNormalizedMacAddress -MacAddress '00-50-56-96-1D-27' | Should -Be '005056961D27'
            (ConvertTo-ToolkitNormalizedMacAddress -MacAddress '00:50:56:96:1d:27') | Should -Be (ConvertTo-ToolkitNormalizedMacAddress -MacAddress '00-50-56-96-1D-27')
        }
    }

    It 'Retorna vazio para MAC invalido' {
        InModuleScope WbaToolkit.Provisioning {
            ConvertTo-ToolkitNormalizedMacAddress -MacAddress 'nao-e-mac' | Should -Be ''
        }
    }
}

Describe 'Resolve-ToolkitNetworkAdapter' {
    It 'Resolve por macAddress normalizado' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @(
                [pscustomobject]@{ Name = 'Ethernet0'; MacAddress = '00-50-56-96-1D-27'; PnPDeviceID = 'PCI\A'; ifIndex = 5 }
                [pscustomobject]@{ Name = 'Ethernet1'; MacAddress = '00-50-56-00-00-01'; PnPDeviceID = 'PCI\B'; ifIndex = 6 }
            ) }
            $result = Resolve-ToolkitNetworkAdapter -Match ([pscustomobject]@{ macAddress = '00:50:56:96:1d:27' })
            $result.Found | Should -BeTrue
            $result.Adapter.Name | Should -Be 'Ethernet0'
        }
    }

    It 'Resolve por alias' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @([pscustomobject]@{ Name = 'Ethernet0'; MacAddress = 'X'; PnPDeviceID = 'PCI\A'; ifIndex = 5 }) }
            $result = Resolve-ToolkitNetworkAdapter -Match ([pscustomobject]@{ alias = 'Ethernet0' })
            $result.Found | Should -BeTrue
        }
    }

    It 'Falha quando nenhum adaptador casa' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @([pscustomobject]@{ Name = 'Ethernet0'; MacAddress = 'AA-BB-CC-DD-EE-FF'; PnPDeviceID = 'PCI\A'; ifIndex = 5 }) }
            $result = Resolve-ToolkitNetworkAdapter -Match ([pscustomobject]@{ macAddress = '00-00-00-00-00-00' })
            $result.Found | Should -BeFalse
        }
    }

    It 'Falha quando multiplos adaptadores casam (ambiguidade)' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @(
                [pscustomobject]@{ Name = 'Ethernet0'; MacAddress = 'AA-BB-CC-DD-EE-FF'; PnPDeviceID = 'PCI\A'; ifIndex = 5 }
                [pscustomobject]@{ Name = 'Ethernet1'; MacAddress = 'AA-BB-CC-DD-EE-FF'; PnPDeviceID = 'PCI\B'; ifIndex = 6 }
            ) }
            $result = Resolve-ToolkitNetworkAdapter -Match ([pscustomobject]@{ macAddress = 'AA-BB-CC-DD-EE-FF' })
            $result.Found | Should -BeFalse
            $result.Message | Should -Match 'ambigua'
        }
    }

    It 'Falha quando nenhum criterio de identificacao e informado' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @() }
            $result = Resolve-ToolkitNetworkAdapter -Match ([pscustomobject]@{})
            $result.Found | Should -BeFalse
        }
    }
}

Describe 'Etapa network.configure' {
    It 'Skipped quando network.adapters nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitNetworkDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Failed quando a identificacao do adaptador e ambigua' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @(
                [pscustomobject]@{ Name = 'E0'; MacAddress = 'AA-AA-AA-AA-AA-AA'; PnPDeviceID = 'A'; ifIndex = 1 }
                [pscustomobject]@{ Name = 'E1'; MacAddress = 'AA-AA-AA-AA-AA-AA'; PnPDeviceID = 'B'; ifIndex = 2 }
            ) }
            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                network       = @{ adapters = @(@{ name = 'Rede'; match = @{ macAddress = 'AA-AA-AA-AA-AA-AA' }; dhcp = $true }) }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $result = Test-ToolkitNetworkDesiredState -Context ([pscustomobject]@{ Config = $config })
            $result.Status | Should -Be 'Failed'
        }
    }

    It 'Compliant quando DHCP ja esta habilitado' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @([pscustomobject]@{ Name = 'E0'; MacAddress = 'AA-AA-AA-AA-AA-AA'; PnPDeviceID = 'A'; ifIndex = 1 }) }
            Mock Get-NetIPInterface { [pscustomobject]@{ Dhcp = 'Enabled' } }
            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                network       = @{ adapters = @(@{ name = 'Rede'; match = @{ alias = 'E0' }; dhcp = $true }) }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitNetworkDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Compliant'
        }
    }

    It 'Changed quando estatico diverge, e Set aplica New-NetIPAddress/Set-DnsClientServerAddress' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @([pscustomobject]@{ Name = 'E0'; MacAddress = 'AA-AA-AA-AA-AA-AA'; PnPDeviceID = 'A'; ifIndex = 1 }) }
            Mock Get-NetIPInterface { [pscustomobject]@{ Dhcp = 'Enabled' } }
            Mock Get-NetIPAddress { @() }
            Mock Get-NetRoute { $null }
            Mock Get-DnsClientServerAddress { [pscustomobject]@{ ServerAddresses = @() } }
            Mock Set-NetIPInterface { }
            Mock New-NetIPAddress { } -Verifiable
            Mock Set-DnsClientServerAddress { } -Verifiable
            Mock Remove-NetIPAddress { }

            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                network       = @{ adapters = @(@{
                    name = 'Rede'; match = @{ alias = 'E0' }; dhcp = $false
                    addresses = @('192.168.4.118/24'); gateway = '192.168.4.1'; dnsServers = @('192.168.4.10')
                }) }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $context = [pscustomobject]@{ Config = $config }

            (Test-ToolkitNetworkDesiredState -Context $context).Status | Should -Be 'Changed'
            Set-ToolkitNetworkDesiredState -Context $context -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }

    It 'Set nao toca em adaptador ja conforme' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetAdapter { @([pscustomobject]@{ Name = 'E0'; MacAddress = 'AA-AA-AA-AA-AA-AA'; PnPDeviceID = 'A'; ifIndex = 1 }) }
            Mock Get-NetIPInterface { [pscustomobject]@{ Dhcp = 'Enabled' } }
            Mock New-NetIPAddress { throw 'Nao deveria ser chamado' }
            Mock Set-NetIPInterface { throw 'Nao deveria ser chamado' }

            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                network       = @{ adapters = @(@{ name = 'Rede'; match = @{ alias = 'E0' }; dhcp = $true }) }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitNetworkDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false } | Should -Not -Throw
        }
    }
}

Describe 'Find-ToolkitProvisioningCertificate' {
    It 'Retorna null quando o repositorio nao existe' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Test-Path { $false }
            Find-ToolkitProvisioningCertificate -Thumbprint ('A' * 40) | Should -BeNullOrEmpty
        }
    }

    It 'Encontra certificado por thumbprint' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @([pscustomobject]@{ Thumbprint = ('A' * 40) }) }
            $found = Find-ToolkitProvisioningCertificate -Thumbprint ('A' * 40)
            $found | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Etapa certificates.install' {
    It 'Skipped quando certificates nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitCertificateDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Changed quando o certificado declarado nao esta instalado, e Set importa via Import-Certificate' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @() }
            Mock Import-Certificate { } -Verifiable

            $thumb = 'A' * 40
            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                certificates  = @(@{ name = 'cert1'; thumbprint = $thumb; source = @{ contentBase64 = [Convert]::ToBase64String([byte[]](1, 2, 3)) } })
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $context = [pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Work = $TestDrive; Secrets = $TestDrive } ; DeploymentId = 'x' }

            (Test-ToolkitCertificateDesiredState -Context $context).Status | Should -Be 'Changed'
            Set-ToolkitCertificateDesiredState -Context $context -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }

    It 'Set usa Import-PfxCertificate quando ha pfxPasswordSecretRef' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @() }
            Mock Resolve-ToolkitProvisioningSecret { ConvertTo-SecureString 'x' -AsPlainText -Force }
            Mock Import-PfxCertificate { } -Verifiable
            Mock Import-Certificate { throw 'Nao deveria ser chamado para PFX' }

            $thumb = 'B' * 40
            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                certificates  = @(@{ name = 'cert1'; thumbprint = $thumb; source = @{ filePath = 'cert.pfx'; pfxPasswordSecretRef = 'ref1' } })
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $context = [pscustomobject]@{ Config = $config; Paths = [pscustomobject]@{ Work = $TestDrive; Secrets = $TestDrive }; DeploymentId = 'x' }

            Set-ToolkitCertificateDesiredState -Context $context -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }

    It 'Compliant quando o certificado ja esta instalado' {
        InModuleScope WbaToolkit.Provisioning {
            $thumb = 'C' * 40
            Mock Test-Path { $true }
            Mock Get-ChildItem { @([pscustomobject]@{ Thumbprint = $thumb }) }

            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                certificates  = @(@{ name = 'cert1'; thumbprint = $thumb; source = @{ contentBase64 = 'AAA=' } })
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $context = [pscustomobject]@{ Config = $config }
            (Test-ToolkitCertificateDesiredState -Context $context).Status | Should -Be 'Compliant'
        }
    }
}

Describe 'Resolve-ToolkitProvisioningSecret' {
    It 'Rejeita secretRef com formato invalido' {
        InModuleScope WbaToolkit.Provisioning {
            { Resolve-ToolkitProvisioningSecret -SecretRef 'ref com espaco!' -Paths ([pscustomobject]@{ Secrets = $TestDrive }) } | Should -Throw '*invalido*'
        }
    }

    It 'Falha quando o envelope nao existe' {
        InModuleScope WbaToolkit.Provisioning {
            { Resolve-ToolkitProvisioningSecret -SecretRef 'inexistente' -Paths ([pscustomobject]@{ Secrets = $TestDrive }) } | Should -Throw '*nao encontrado*'
        }
    }

    It 'Decifra o envelope e devolve SecureString' {
        InModuleScope WbaToolkit.Provisioning {
            $secretsDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -Path $secretsDir -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $secretsDir 'meu-ref.cms') -Value 'envelope-fake' -Encoding UTF8
            Mock Unprotect-CmsMessage { 'segredo-em-claro' }

            $result = Resolve-ToolkitProvisioningSecret -SecretRef 'meu-ref' -Paths ([pscustomobject]@{ Secrets = $secretsDir })
            $result | Should -BeOfType [System.Security.SecureString]
        }
    }
}

Describe 'Test/Set-ToolkitFirewallRuleState' {
    It 'Regra ausente e desejada desabilitada e Compliant' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetFirewallRule { }
            (Test-ToolkitFirewallRuleState -Name 'R1' -Enabled $false).IsCompliant | Should -BeTrue
        }
    }

    It 'Regra ausente e desejada habilitada nao e Compliant' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetFirewallRule { }
            (Test-ToolkitFirewallRuleState -Name 'R1' -Enabled $true -Profile @('Domain')).IsCompliant | Should -BeFalse
        }
    }

    It 'Set cria a regra quando ausente e desejada habilitada' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetFirewallRule { }
            Mock New-NetFirewallRule { } -Verifiable
            Set-ToolkitFirewallRuleState -Name 'R1' -Enabled $true -Protocol 'TCP' -LocalPort '5986' -Profile @('Domain') -Confirm:$false
            Should -InvokeVerifiable
        }
    }

    It 'Set desabilita a regra existente quando desejada desabilitada' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetFirewallRule { [pscustomobject]@{ Name = 'R1'; Enabled = $true } }
            Mock Disable-NetFirewallRule { } -Verifiable
            Set-ToolkitFirewallRuleState -Name 'R1' -Enabled $false -Confirm:$false
            Should -InvokeVerifiable
        }
    }
}

Describe 'Etapa remoteaccess.winrm' {
    It 'Compliant quando desabilitado por ausencia de secao (nunca Skipped)' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-WSManInstance { }
            Mock Get-NetFirewallRule { }
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            $result = Test-ToolkitWinRmDesiredState -Context $context
            $result.Status | Should -Be 'Compliant'
        }
    }

    It 'Changed quando habilitado mas sem listener/regra' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-WSManInstance { }
            Mock Get-NetFirewallRule { }
            $thumb = 'D' * 40
            $config = @{ schemaVersion = 1; deploymentId = 'x'; remoteAccess = @{ winrm = @{ enabled = $true; certificateThumbprint = $thumb } } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitWinRmDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Changed'
        }
    }

    It 'Set cria o listener HTTPS e a regra de firewall' {
        InModuleScope WbaToolkit.Provisioning {
            $thumb = 'E' * 40
            Mock Get-WSManInstance { }
            Mock Find-ToolkitProvisioningCertificate { [pscustomobject]@{ Thumbprint = $thumb } }
            Mock New-WSManInstance { } -Verifiable
            Mock Get-NetFirewallRule { }
            Mock New-NetFirewallRule { } -Verifiable

            $config = @{ schemaVersion = 1; deploymentId = 'x'; remoteAccess = @{ winrm = @{ enabled = $true; certificateThumbprint = $thumb } } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            Set-ToolkitWinRmDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }

    It 'Set lanca erro claro quando o certificado referenciado nao esta instalado' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-WSManInstance { }
            Mock Find-ToolkitProvisioningCertificate { $null }
            $thumb = 'F' * 40
            $config = @{ schemaVersion = 1; deploymentId = 'x'; remoteAccess = @{ winrm = @{ enabled = $true; certificateThumbprint = $thumb } } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            { Set-ToolkitWinRmDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false } | Should -Throw '*nao esta instalado*'
        }
    }
}

Describe 'Etapa remoteaccess.rdp' {
    It 'Compliant quando desabilitado por ausencia de secao (nunca Skipped)' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-ItemProperty { [pscustomobject]@{ fDenyTSConnections = 1 } }
            Mock Get-NetFirewallRule { }
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitRdpDesiredState -Context $context).Status | Should -Be 'Compliant'
        }
    }

    It 'Changed quando habilitado na config mas desabilitado no sistema' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-ItemProperty { [pscustomobject]@{ fDenyTSConnections = 1 } }
            Mock Get-NetFirewallRule { }
            $config = @{ schemaVersion = 1; deploymentId = 'x'; remoteAccess = @{ rdp = @{ enabled = $true } } } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            (Test-ToolkitRdpDesiredState -Context ([pscustomobject]@{ Config = $config })).Status | Should -Be 'Changed'
        }
    }

    It 'Set habilita fDenyTSConnections=0 e as regras de firewall' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Set-ItemProperty { } -Verifiable
            Mock Get-NetFirewallRule { [pscustomobject]@{ Name = 'RemoteDesktop-UserMode-In-TCP' } }
            Mock Enable-NetFirewallRule { } -Verifiable
            Mock Set-NetFirewallRule { }

            $config = @{ schemaVersion = 1; deploymentId = 'x'; remoteAccess = @{ rdp = @{ enabled = $true; firewallProfile = @('Domain') } } } |
                ConvertTo-Json -Depth 10 | ConvertFrom-Json
            Set-ToolkitRdpDesiredState -Context ([pscustomobject]@{ Config = $config }) -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }
}

Describe 'Etapa firewall.rules' {
    It 'Skipped quando firewall.rules nao esta declarado' {
        InModuleScope WbaToolkit.Provisioning {
            $context = [pscustomobject]@{ Config = (@{ schemaVersion = 1; deploymentId = 'x' } | ConvertTo-Json | ConvertFrom-Json) }
            (Test-ToolkitFirewallRulesDesiredState -Context $context).Status | Should -Be 'Skipped'
        }
    }

    It 'Changed quando uma regra declarada nao existe, e Set so aplica as pendentes' {
        InModuleScope WbaToolkit.Provisioning {
            Mock Get-NetFirewallRule { } -ParameterFilter { $Name -eq 'App-Pendente' }
            Mock Get-NetFirewallRule { [pscustomobject]@{ Name = 'App-Ok'; Enabled = $true } } -ParameterFilter { $Name -eq 'App-Ok' }
            Mock Get-NetFirewallProfile { @([pscustomobject]@{ Name = 'Domain' }) }
            Mock New-NetFirewallRule { } -Verifiable

            $config = @{
                schemaVersion = 1; deploymentId = 'x'
                firewall      = @{ rules = @(
                    @{ name = 'App-Ok'; enabled = $true; profile = @('Domain') },
                    @{ name = 'App-Pendente'; enabled = $true; protocol = 'TCP'; localPort = '8443'; profile = @('Domain') }
                ) }
            } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $context = [pscustomobject]@{ Config = $config }

            (Test-ToolkitFirewallRulesDesiredState -Context $context).Status | Should -Be 'Changed'
            Set-ToolkitFirewallRulesDesiredState -Context $context -Confirm:$false | Out-Null
            Should -InvokeVerifiable
        }
    }
}
