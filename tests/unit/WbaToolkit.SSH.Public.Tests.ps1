#requires -version 5.1

# BCK-070: funcoes publicas do WbaToolkit.SSH sem teste. Servicos, capability e firewall sao simulados;
# arquivos vao para o TestDrive; Test-SshConnectivity usa servidores TCP locais.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.SSH\WbaToolkit.SSH.psd1') -Force

    $script:chaveA = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa usuario@a'
    $script:chaveB = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABbbbbbbbbbbbbbbbbbbbbbbbbbbbb usuario@b'

    function script:New-SshTestPaths {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $programData = Join-Path $base 'ProgramData\ssh'
        New-Item -Path $programData -ItemType Directory -Force | Out-Null
        [pscustomobject]@{
            SshdConfig          = Join-Path $programData 'sshd_config'
            SshdConfigBackupDir = Join-Path $programData 'backups'
            HostKeysDir         = $programData
            AdminAuthorizedKeys = Join-Path $programData 'administrators_authorized_keys'
            UserSshDir          = Join-Path $base 'perfil\.ssh'
            UserAuthorizedKeys  = Join-Path $base 'perfil\.ssh\authorized_keys'
            UserConfig          = Join-Path $base 'perfil\.ssh\config'
            UserKnownHosts      = Join-Path $base 'perfil\.ssh\known_hosts'
            SshLogsDir          = Join-Path $programData 'logs'
            Perfil              = Join-Path $base 'perfil'
        }
    }

    # CimInstance real: os cmdlets de firewall recebem pelo pipeline parametros tipados como CimInstance.
    function script:New-TestCim([string]$ClassName, [hashtable]$Properties) {
        $obj = [Microsoft.Management.Infrastructure.CimInstance]::new($ClassName, 'root/standardcimv2')
        foreach ($key in $Properties.Keys) {
            $obj.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create($key, $Properties[$key], [Microsoft.Management.Infrastructure.CimFlags]::None))
        }
        $obj
    }

    function script:New-FirewallRuleCim {
        New-TestCim 'MSFT_NetFirewallRule' @{ DisplayName = 'OpenSSH Server (sshd)'; Enabled = 1 }
    }

    function script:Test-Utf8Bom([string]$Path) {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    }
}

Describe 'Add-SshAuthorizedKey' {
    BeforeEach {
        $script:paths = New-SshTestPaths
        Mock -ModuleName WbaToolkit.SSH Get-SshConfigPath { $script:paths }
        Mock -ModuleName WbaToolkit.SSH Get-SshUserProfilePath { $script:paths.Perfil }
        Mock -ModuleName WbaToolkit.SSH Test-SshUserIsAdmin { $true }
        Mock -ModuleName WbaToolkit.SSH Set-Acl { $script:aclGravada = $AclObject }
        $script:aclGravada = $null
    }

    It 'Recusa chave ausente ou em formato invalido' {
        (Add-SshAuthorizedKey).Success | Should -BeFalse
        $r = Add-SshAuthorizedKey -PublicKey 'nao-e-uma-chave'
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'Formato'
        Test-Path -LiteralPath $script:paths.AdminAuthorizedKeys | Should -BeFalse
    }

    It 'Recusa arquivo de chave inexistente' {
        $r = Add-SshAuthorizedKey -PublicKeyPath (Join-Path $TestDrive 'nao-existe.pub')
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'nao encontrado'
    }

    It 'Le a chave do arquivo .pub' {
        $pub = Join-Path $TestDrive 'id.pub'
        [System.IO.File]::WriteAllText($pub, "# comentario`r`n$script:chaveA`r`n")

        (Add-SshAuthorizedKey -PublicKeyPath $pub).Success | Should -BeTrue
        [System.IO.File]::ReadAllLines($script:paths.AdminAuthorizedKeys) | Should -Be @($script:chaveA)
    }

    It 'Administrador: grava administrators_authorized_keys sem BOM e com ACL por SID (ADR 0034)' {
        $r = Add-SshAuthorizedKey -PublicKey $script:chaveA

        $r.Success | Should -BeTrue
        $r.KeyFile | Should -Be $script:paths.AdminAuthorizedKeys
        Test-Utf8Bom $script:paths.AdminAuthorizedKeys | Should -BeFalse
        [System.IO.File]::ReadAllText($script:paths.AdminAuthorizedKeys) | Should -Be "$script:chaveA`r`n"

        $script:aclGravada.AreAccessRulesProtected | Should -BeTrue
        $sids = @($script:aclGravada.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) |
            ForEach-Object { $_.IdentityReference.Value }) | Sort-Object
        $sids | Should -Be @('S-1-5-18', 'S-1-5-32-544')
    }

    It 'Nao duplica chave existente' {
        Add-SshAuthorizedKey -PublicKey $script:chaveA | Out-Null

        $r = Add-SshAuthorizedKey -PublicKey "  $script:chaveA  "

        $r.Message | Should -Match 'ja existe'
        @([System.IO.File]::ReadAllLines($script:paths.AdminAuthorizedKeys)).Count | Should -Be 1
    }

    It 'Acrescenta em linha nova quando o arquivo nao termina com quebra de linha' {
        [System.IO.File]::WriteAllText($script:paths.AdminAuthorizedKeys, $script:chaveA)

        Add-SshAuthorizedKey -PublicKey $script:chaveB | Out-Null

        [System.IO.File]::ReadAllLines($script:paths.AdminAuthorizedKeys) | Should -Be @($script:chaveA, $script:chaveB)
    }

    It 'Usuario comum: grava no authorized_keys do perfil resolvido, sem mexer na ACL' {
        Mock -ModuleName WbaToolkit.SSH Test-SshUserIsAdmin { $false }

        $r = Add-SshAuthorizedKey -PublicKey $script:chaveB -UserName 'fulano'

        $r.KeyFile | Should -Be (Join-Path $script:paths.Perfil '.ssh\authorized_keys')
        [System.IO.File]::ReadAllLines($r.KeyFile) | Should -Be @($script:chaveB)
        Should -Invoke -ModuleName WbaToolkit.SSH Get-SshUserProfilePath -ParameterFilter { $UserName -eq 'fulano' }
        Should -Invoke -ModuleName WbaToolkit.SSH Set-Acl -Times 0 -Exactly
    }
}

Describe 'Get-SshAuthorizedKey' {
    BeforeEach {
        $script:paths = New-SshTestPaths
        Mock -ModuleName WbaToolkit.SSH Get-SshConfigPath { $script:paths }
        Mock -ModuleName WbaToolkit.SSH Get-SshUserProfilePath { $script:paths.Perfil }
        Mock -ModuleName WbaToolkit.SSH Test-SshUserIsAdmin { $true }
    }

    It 'Sem arquivo devolve lista vazia' {
        @(Get-SshAuthorizedKey).Count | Should -Be 0
    }

    It 'Lista as chaves com indice, tipo, comentario e impressao resumida' {
        [System.IO.File]::WriteAllText($script:paths.AdminAuthorizedKeys, "# chaves`r`n$script:chaveA`r`n`r`nlixo`r`n$script:chaveB`r`n")

        $keys = @(Get-SshAuthorizedKey)

        $keys.Count | Should -Be 2
        $keys[0].Index | Should -Be 0
        $keys[0].Type | Should -Be 'ssh-ed25519'
        $keys[0].Comment | Should -Be 'usuario@a'
        $keys[0].Fingerprint | Should -Be 'AAAAC3NzaC1lZDI1...'
        $keys[1].Index | Should -Be 1
        $keys[1].FullKey | Should -Be $script:chaveB
    }

    It 'Usuario comum le do perfil resolvido' {
        Mock -ModuleName WbaToolkit.SSH Test-SshUserIsAdmin { $false }
        New-Item -Path (Join-Path $script:paths.Perfil '.ssh') -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:paths.Perfil '.ssh\authorized_keys'), $script:chaveB)

        @(Get-SshAuthorizedKey -UserName 'fulano').FullKey | Should -Be @($script:chaveB)
    }
}

Describe 'Get-SshUserProfilePath (ADR 0034)' {
    It 'Usuario atual usa USERPROFILE' {
        InModuleScope WbaToolkit.SSH { Get-SshUserProfilePath -UserName $env:USERNAME } | Should -Be $env:USERPROFILE
    }

    It 'Resolve o perfil pelo SID, mesmo com nome de conta localizado' {
        $system = ([System.Security.Principal.SecurityIdentifier]'S-1-5-18').Translate([System.Security.Principal.NTAccount]).Value

        $perfil = InModuleScope WbaToolkit.SSH -Parameters @{ Conta = $system } { param($Conta) Get-SshUserProfilePath -UserName $Conta }

        $perfil | Should -Be (Join-Path $env:windir 'system32\config\systemprofile')
    }

    It 'Conta sem perfil cai na raiz de perfis do usuario atual' {
        $perfil = InModuleScope WbaToolkit.SSH { Get-SshUserProfilePath -UserName 'wba-conta-que-nao-existe' }

        $perfil | Should -Be (Join-Path (Split-Path -Parent $env:USERPROFILE) 'wba-conta-que-nao-existe')
    }
}

Describe 'Get-SshdConfig' {
    BeforeEach {
        $script:paths = New-SshTestPaths
        Mock -ModuleName WbaToolkit.SSH Get-SshConfigPath { $script:paths }
    }

    It 'Arquivo ausente: Exists falso e configuracao vazia' {
        $r = Get-SshdConfig

        $r.Exists | Should -BeFalse
        $r.Path | Should -Be $script:paths.SshdConfig
        $r.Config.Count | Should -Be 0
        @($r.MatchBlocks).Count | Should -Be 0
    }

    It 'Separa diretivas globais das de blocos Match e agrupa repetidas' {
        @(
            '# comentario'
            'Port 22'
            'Port 2222'
            'PasswordAuthentication yes'
            '#PermitRootLogin no'
            ''
            'Match Group administrators'
            '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
            'Match User backup'
            '       PasswordAuthentication no'
        ) | Set-Content -LiteralPath $script:paths.SshdConfig -Encoding ASCII

        $r = Get-SshdConfig

        $r.Exists | Should -BeTrue
        $r.Config['Port'] | Should -Be @('22', '2222')
        $r.Config['PasswordAuthentication'] | Should -Be 'yes'
        $r.Config.ContainsKey('PermitRootLogin') | Should -BeFalse
        $r.Config.ContainsKey('AuthorizedKeysFile') | Should -BeFalse
        @($r.MatchBlocks).Count | Should -Be 2
        $r.MatchBlocks[0].Criteria | Should -Be 'Group administrators'
        $r.MatchBlocks[0].Config['AuthorizedKeysFile'] | Should -Be '__PROGRAMDATA__/ssh/administrators_authorized_keys'
        $r.MatchBlocks[1].Config['PasswordAuthentication'] | Should -Be 'no'
        @($r.RawLines).Count | Should -Be 10
    }

    It 'Aceita -Path explicito' {
        $outro = Join-Path $TestDrive 'outro_sshd_config'
        Set-Content -LiteralPath $outro -Value 'Port 2200' -Encoding ASCII

        (Get-SshdConfig -Path $outro).Config['Port'] | Should -Be '2200'
    }
}

Describe 'Get-SshServerStatus' {
    BeforeEach {
        $script:paths = New-SshTestPaths
        Mock -ModuleName WbaToolkit.SSH Get-SshConfigPath { $script:paths }
        Mock -ModuleName WbaToolkit.SSH Get-WindowsCapability { [pscustomobject]@{ Name = 'OpenSSH.Server~~~~0.0.1.0'; State = 'Installed' } }
        Mock -ModuleName WbaToolkit.SSH Get-Service { [pscustomobject]@{ Name = 'sshd'; Status = 'Running'; StartType = 'Automatic' } }
        Mock -ModuleName WbaToolkit.SSH Get-NetFirewallRule { [pscustomobject]@{ DisplayName = 'OpenSSH Server (sshd)'; Enabled = 'True' } }
    }

    It 'Instalado: le a primeira porta, chaves de host e chaves de administrador' {
        "Port 2222`r`nPort 2200`r`n" | Set-Content -LiteralPath $script:paths.SshdConfig -NoNewline -Encoding ASCII
        'x' | Set-Content -LiteralPath (Join-Path $script:paths.HostKeysDir 'ssh_host_ed25519_key')
        'x' | Set-Content -LiteralPath (Join-Path $script:paths.HostKeysDir 'ssh_host_rsa_key')
        "$script:chaveA`r`n# comentario`r`n$script:chaveB" | Set-Content -LiteralPath $script:paths.AdminAuthorizedKeys

        $s = Get-SshServerStatus

        $s.FeatureInstalled | Should -BeTrue
        $s.ServiceStatus | Should -Be 'Running'
        $s.ServiceStartType | Should -Be 'Automatic'
        $s.Port | Should -Be 2222
        $s.FirewallRuleExists | Should -BeTrue
        $s.HostKeysCount | Should -Be 2
        ($s.HostKeys.Type | Sort-Object) -join ',' | Should -Be 'ed25519,rsa'
        $s.AdminKeysCount | Should -Be 2
        $s.ConfigExists | Should -BeTrue
    }

    It 'Nao instalado: estados NotFound e porta padrao' {
        Mock -ModuleName WbaToolkit.SSH Get-WindowsCapability { }
        Mock -ModuleName WbaToolkit.SSH Get-Service { throw 'servico inexistente' }
        Mock -ModuleName WbaToolkit.SSH Get-NetFirewallRule { throw 'sem regra' }

        $s = Get-SshServerStatus

        $s.FeatureInstalled | Should -BeFalse
        $s.FeatureState | Should -Be 'NotFound'
        $s.ServiceStatus | Should -Be 'NotFound'
        $s.Port | Should -Be 22
        $s.FirewallRuleExists | Should -BeFalse
        $s.HostKeysCount | Should -Be 0
        $s.ConfigExists | Should -BeFalse
    }
}

Describe 'Install-SshServer' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.SSH Get-SshServerStatus { [pscustomobject]@{ FeatureInstalled = $false } }
        Mock -ModuleName WbaToolkit.SSH Test-IsAdministrator { $true }
        Mock -ModuleName WbaToolkit.SSH Add-WindowsCapability { [pscustomobject]@{ State = 'Installed' } }
    }

    It 'Ja instalado: nao reinstala' {
        Mock -ModuleName WbaToolkit.SSH Get-SshServerStatus { [pscustomobject]@{ FeatureInstalled = $true } }

        (Install-SshServer).Message | Should -Match 'ja esta instalado'
        Should -Invoke -ModuleName WbaToolkit.SSH Add-WindowsCapability -Times 0 -Exactly
    }

    It 'Sem administrador: recusa' {
        Mock -ModuleName WbaToolkit.SSH Test-IsAdministrator { $false }

        (Install-SshServer).Success | Should -BeFalse
        Should -Invoke -ModuleName WbaToolkit.SSH Add-WindowsCapability -Times 0 -Exactly
    }

    It 'Instala a capability OpenSSH.Server' {
        $r = Install-SshServer

        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName WbaToolkit.SSH Add-WindowsCapability -Times 1 -Exactly -ParameterFilter { $Online -and $Name -eq 'OpenSSH.Server~~~~0.0.1.0' }
    }

    It 'Falha da instalacao vira resultado sem sucesso' {
        Mock -ModuleName WbaToolkit.SSH Add-WindowsCapability { throw 'sem acesso ao Windows Update' }

        $r = Install-SshServer
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'sem acesso ao Windows Update'
    }
}

Describe 'Enable-SshServer' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.SSH Test-IsAdministrator { $true }
        Mock -ModuleName WbaToolkit.SSH Get-SshServerStatus { [pscustomobject]@{ FeatureInstalled = $true } }
        Mock -ModuleName WbaToolkit.SSH Set-Service { }
        Mock -ModuleName WbaToolkit.SSH Start-Service { }
        Mock -ModuleName WbaToolkit.SSH Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock -ModuleName WbaToolkit.SSH Get-NetFirewallRule { }
        Mock -ModuleName WbaToolkit.SSH New-NetFirewallRule { }
        Mock -ModuleName WbaToolkit.SSH Get-NetFirewallPortFilter { New-TestCim 'MSFT_NetProtocolPortFilter' @{ LocalPort = '22' } }
        Mock -ModuleName WbaToolkit.SSH Set-NetFirewallRule { }
        Mock -ModuleName WbaToolkit.SSH Set-NetFirewallPortFilter { }
    }

    It 'Sem administrador: recusa sem tocar no servico' {
        Mock -ModuleName WbaToolkit.SSH Test-IsAdministrator { $false }

        (Enable-SshServer).Success | Should -BeFalse
        Should -Invoke -ModuleName WbaToolkit.SSH Set-Service -Times 0 -Exactly
    }

    It 'Sem OpenSSH instalado: recusa' {
        Mock -ModuleName WbaToolkit.SSH Get-SshServerStatus { [pscustomobject]@{ FeatureInstalled = $false } }

        (Enable-SshServer).Message | Should -Match 'Install-SshServer'
        Should -Invoke -ModuleName WbaToolkit.SSH Start-Service -Times 0 -Exactly
    }

    It 'Configura o servico automatico, inicia e cria a regra de firewall na porta' {
        $r = Enable-SshServer -Port 2222

        $r.Success | Should -BeTrue
        $r.Port | Should -Be 2222
        Should -Invoke -ModuleName WbaToolkit.SSH Set-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'sshd' -and $StartupType -eq 'Automatic' }
        Should -Invoke -ModuleName WbaToolkit.SSH Start-Service -Times 1 -Exactly
        Should -Invoke -ModuleName WbaToolkit.SSH New-NetFirewallRule -Times 1 -Exactly -ParameterFilter { $LocalPort -eq 2222 -and $Direction -eq 'Inbound' }
    }

    It 'Regra existente em outra porta: atualiza a porta' {
        Mock -ModuleName WbaToolkit.SSH Get-NetFirewallRule { New-FirewallRuleCim }

        (Enable-SshServer -Port 2222).Success | Should -BeTrue

        Should -Invoke -ModuleName WbaToolkit.SSH New-NetFirewallRule -Times 0 -Exactly
        Should -Invoke -ModuleName WbaToolkit.SSH Set-NetFirewallPortFilter -Times 1 -Exactly -ParameterFilter { $LocalPort -eq 2222 }
    }

    It 'Regra existente na mesma porta: nao altera' {
        Mock -ModuleName WbaToolkit.SSH Get-NetFirewallRule { New-FirewallRuleCim }

        Enable-SshServer -Port 22 | Out-Null

        Should -Invoke -ModuleName WbaToolkit.SSH Set-NetFirewallPortFilter -Times 0 -Exactly
    }

    It 'Junta os erros e devolve sem sucesso' {
        Mock -ModuleName WbaToolkit.SSH Set-Service { throw 'acesso negado' }
        Mock -ModuleName WbaToolkit.SSH Start-Service { throw 'nao iniciou' }

        $r = Enable-SshServer
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'StartupType: acesso negado'
        $r.Message | Should -Match 'Start: nao iniciou'
    }
}

Describe 'Disable-SshServer' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.SSH Test-IsAdministrator { $true }
        Mock -ModuleName WbaToolkit.SSH Stop-Service { }
        Mock -ModuleName WbaToolkit.SSH Set-Service { }
        Mock -ModuleName WbaToolkit.SSH Remove-NetFirewallRule { }
    }

    It 'Sem administrador: recusa' {
        Mock -ModuleName WbaToolkit.SSH Test-IsAdministrator { $false }

        (Disable-SshServer).Success | Should -BeFalse
        Should -Invoke -ModuleName WbaToolkit.SSH Stop-Service -Times 0 -Exactly
    }

    It 'Para o servico, deixa manual e preserva a regra de firewall' {
        (Disable-SshServer).Success | Should -BeTrue

        Should -Invoke -ModuleName WbaToolkit.SSH Stop-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'sshd' }
        Should -Invoke -ModuleName WbaToolkit.SSH Set-Service -Times 1 -Exactly -ParameterFilter { $StartupType -eq 'Manual' }
        Should -Invoke -ModuleName WbaToolkit.SSH Remove-NetFirewallRule -Times 0 -Exactly
    }

    It '-RemoveFirewallRule remove a regra' {
        Disable-SshServer -RemoveFirewallRule | Out-Null

        Should -Invoke -ModuleName WbaToolkit.SSH Remove-NetFirewallRule -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'OpenSSH Server (sshd)' }
    }

    It 'Falha ao mudar o tipo de inicio vira resultado sem sucesso' {
        Mock -ModuleName WbaToolkit.SSH Set-Service { throw 'acesso negado' }

        (Disable-SshServer).Message | Should -Match 'Service: acesso negado'
    }
}

Describe 'New-SshUserKey' {
    BeforeAll {
        $script:temKeygen = [bool](Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)
    }

    BeforeEach {
        $script:perfil = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock -ModuleName WbaToolkit.SSH Get-SshUserProfilePath { $script:perfil }
    }

    It '-WhatIf nao cria nada' {
        $r = New-SshUserKey -WhatIf

        $r.Generated | Should -BeFalse
        $r.KeyPath | Should -Be (Join-Path $script:perfil '.ssh\id_ed25519')
        Test-Path -LiteralPath $script:perfil | Should -BeFalse
    }

    It 'Chave existente sem -Force e preservada' {
        New-Item -Path (Join-Path $script:perfil '.ssh') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:perfil '.ssh\id_ed25519') -Value 'privada'
        Set-Content -LiteralPath (Join-Path $script:perfil '.ssh\id_ed25519.pub') -Value 'ssh-ed25519 AAAA antiga'
        Mock -ModuleName WbaToolkit.SSH Start-Process { throw 'nao deveria gerar' }

        $r = New-SshUserKey -Confirm:$false

        $r.Generated | Should -BeFalse
        $r.PublicKey | Should -Be 'ssh-ed25519 AAAA antiga'
        Get-Content -LiteralPath (Join-Path $script:perfil '.ssh\id_ed25519') | Should -Be 'privada'
    }

    It 'Gera o par de chaves com ssh-keygen' {
        if (-not $script:temKeygen) { Set-ItResult -Skipped -Because 'ssh-keygen.exe indisponivel'; return }

        $r = New-SshUserKey -KeyName 'id_teste' -Confirm:$false

        $r.Success | Should -BeTrue
        $r.Generated | Should -BeTrue
        Test-Path -LiteralPath $r.KeyPath | Should -BeTrue
        $r.PublicKey | Should -Match '^ssh-ed25519 '
    }

    It '-Force regenera sem travar e guarda backup da chave anterior' {
        if (-not $script:temKeygen) { Set-ItResult -Skipped -Because 'ssh-keygen.exe indisponivel'; return }
        # Roda num powershell.exe filho com tempo limite: antes da correcao o ssh-keygen ficava parado
        # perguntando se podia sobrescrever. Job nao serve, porque o ssh-keygen sem console trava.
        # USERPROFILE aponta para o TestDrive, entao o perfil resolvido e o do teste.
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $saida = Join-Path $TestDrive 'force.json'
        $sonda = Join-Path $TestDrive 'force.ps1'
        $corpo = @"
`$env:USERPROFILE = '$($script:perfil)'
Import-Module '$repoRoot\modules\WbaToolkit.Core\WbaToolkit.Core.psd1'
Import-Module '$repoRoot\modules\WbaToolkit.SSH\WbaToolkit.SSH.psd1'
`$primeira = New-SshUserKey -Confirm:`$false
`$segunda = New-SshUserKey -Force -Confirm:`$false
`$backups = @(Get-ChildItem (Join-Path `$env:USERPROFILE '.ssh') -Filter 'id_ed25519.bak.*' | ForEach-Object Name)
[pscustomobject]@{ Primeira = [string]`$primeira.PublicKey; Segunda = `$segunda; Backups = `$backups } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath '$saida'
"@
        [System.IO.File]::WriteAllText($sonda, $corpo, [System.Text.UTF8Encoding]::new($true))
        $proc = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$sonda`"") -WindowStyle Hidden -PassThru
        $terminou = $proc.WaitForExit(60000)
        if (-not $terminou) {
            $proc.Kill()
            Get-CimInstance Win32_Process -Filter "Name = 'ssh-keygen.exe'" | Where-Object { $_.ParentProcessId -eq $proc.Id } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        }
        $terminou | Should -BeTrue -Because 'New-SshUserKey -Force nao pode ficar esperando resposta do ssh-keygen'
        $r = Get-Content -LiteralPath $saida -Raw | ConvertFrom-Json
        $r.Segunda.Success | Should -BeTrue
        $r.Segunda.Generated | Should -BeTrue
        $r.Segunda.PublicKey | Should -Not -Be $r.Primeira
        @($r.Backups | Where-Object { $_ -notlike '*.pub' }).Count | Should -Be 1
        @($r.Backups | Where-Object { $_ -like '*.pub' }).Count | Should -Be 1
    }
}

Describe 'Test-SshConnectivity' {
    BeforeEach {
        $script:listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $script:listener.Start()
        $script:porta = ([System.Net.IPEndPoint]$script:listener.LocalEndpoint).Port
        $script:servidor = $null
    }

    AfterEach {
        $script:listener.Stop()
        if ($script:servidor) { $script:servidor.Dispose() }
    }

    It 'Le o banner SSH e mede o tempo de conexao' {
        $script:servidor = [powershell]::Create().AddScript({
            param($Listener)
            $cliente = $Listener.AcceptTcpClient()
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("SSH-2.0-OpenSSH_for_Windows_Teste`r`n")
            $cliente.GetStream().Write($bytes, 0, $bytes.Length)
            Start-Sleep -Milliseconds 500
            $cliente.Close()
        }).AddArgument($script:listener)
        $null = $script:servidor.BeginInvoke()

        $r = Test-SshConnectivity -Host '127.0.0.1' -Port $script:porta -TimeoutMs 3000

        $r.PortOpen | Should -BeTrue
        $r.Banner | Should -Be 'SSH-2.0-OpenSSH_for_Windows_Teste'
        $r.ServiceResponding | Should -BeTrue
        $r.ConnectionMs | Should -BeOfType [int]
        $r.ConnectionMs | Should -BeLessThan 3000
    }

    It 'Porta aberta com outro protocolo nao conta como SSH respondendo' {
        $script:servidor = [powershell]::Create().AddScript({
            param($Listener)
            $cliente = $Listener.AcceptTcpClient()
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 400 Bad Request`r`n")
            $cliente.GetStream().Write($bytes, 0, $bytes.Length)
            Start-Sleep -Milliseconds 500
            $cliente.Close()
        }).AddArgument($script:listener)
        $null = $script:servidor.BeginInvoke()

        $r = Test-SshConnectivity -Host '127.0.0.1' -Port $script:porta -TimeoutMs 3000

        $r.PortOpen | Should -BeTrue
        $r.ServiceResponding | Should -BeFalse
    }

    It 'Porta aberta sem banner: PortOpen verdadeiro, sem banner' {
        $r = Test-SshConnectivity -Host '127.0.0.1' -Port $script:porta -TimeoutMs 500

        $r.PortOpen | Should -BeTrue
        $r.Banner | Should -BeNullOrEmpty
        $r.ServiceResponding | Should -BeFalse
    }

    It 'Porta fechada: PortOpen falso e sem tempo de conexao' {
        $script:listener.Stop()

        $r = Test-SshConnectivity -Host '127.0.0.1' -Port $script:porta -TimeoutMs 1000

        $r.PortOpen | Should -BeFalse
        $r.ConnectionMs | Should -BeNullOrEmpty
        $r.Host | Should -Be '127.0.0.1'
        $r.Port | Should -Be $script:porta
    }
}
