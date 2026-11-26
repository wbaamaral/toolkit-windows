#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot = Get-XtudoRepoRoot
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/sincronizar-relogio.ps1'
    $script:functionPath = Join-Path $script:repoRoot 'modules/WbaToolkit.Maintenance/Public/Sync-ComputerTime.ps1'
    $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    $script:functionContent = Get-Content -LiteralPath $script:functionPath -Raw
    $script:launcherContent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'xtudo.ps1') -Raw
    $script:maintenanceManifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1') -Raw
}

Describe 'Sincronização de relógio' {
    It 'mantém o script oficial e a função no módulo de manutenção' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
        Test-Path -LiteralPath $script:functionPath | Should -BeTrue
        $script:maintenanceManifest | Should -Match "'Sync-ComputerTime'"
    }

    It 'usa diagnóstico sem alteração por padrão e correção explícita' {
        $script:functionContent | Should -Match '\[switch\]\$Apply'
        $script:scriptContent | Should -Match '\[switch\]\$Corrigir'
        $script:scriptContent | Should -Match 'Test-IsAdministrator'
    }

    It 'separa hierarquia AD de NTP externo' {
        $script:functionContent | Should -Match 'PartOfDomain'
        $script:functionContent | Should -Match 'syncfromflags:domhier'
        $script:functionContent | Should -Match 'pool\.ntp\.br'
        $script:functionContent | Should -Match 'time\.windows\.com'
    }

    It 'protege o fuso contra alteração implícita' {
        $script:functionContent | Should -Match 'TimeZoneId'
        $script:functionContent | Should -Match 'Get-TimeZone -ListAvailable'
        $script:functionContent | Should -Match 'Set-TimeZone -Id'
        $script:scriptContent | Should -Match '\$TimeZoneId'
        $script:scriptContent | Should -Match '\$Corrigir'
    }

    It 'expõe a ferramenta no launcher' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/sincronizar-relogio\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Sincronizar relógio'"
        $script:launcherContent | Should -Match "'w32time'"
    }

    It 'mantém a saída de relatórios no padrão do toolkit' {
        $script:scriptContent | Should -Match 'Initialize-ToolkitReportSession'
        $script:scriptContent | Should -Match 'sincronizar-relogio\.json'
        $script:scriptContent | Should -Match 'sincronizar-relogio\.txt'
        $script:scriptContent | Should -Match 'sincronizar-relogio\.html'
    }
}

Describe 'Sync-ComputerTime -Apply (BCK-065/A-NET-2)' {
    BeforeAll {
        . (Join-Path $script:repoRoot 'modules/WbaToolkit.Core/Public/Test-ToolkitLabMock.ps1')
        . (Join-Path $script:repoRoot 'modules/WbaToolkit.Maintenance/Private/Invoke-W32tm.ps1')
        . $script:functionPath
        $script:savedMockAd = $env:WBA_MOCK_AD
        $env:WBA_MOCK_AD = $null
    }

    AfterAll {
        $env:WBA_MOCK_AD = $script:savedMockAd
    }

    BeforeEach {
        $script:calls = New-Object System.Collections.Generic.List[string]
        $script:sourceAfter = 'pool.ntp.br,0x8'
        $script:resyncExit = 0
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'PC01'; PartOfDomain = $false; Domain = 'WORKGROUP' } }
        Mock Get-Service { [pscustomobject]@{ Name = 'W32Time'; Status = 'Stopped' } }
        Mock Get-TimeZone -ParameterFilter { -not $ListAvailable } { [pscustomobject]@{ Id = 'UTC' } }
        Mock Get-TimeZone -ParameterFilter { $ListAvailable } { [pscustomobject]@{ Id = 'E. South America Standard Time' } }
        Mock Set-Service { $script:calls.Add('Set-Service') }
        Mock Start-Service { $script:calls.Add('Start-Service') }
        Mock Set-TimeZone { $script:calls.Add('Set-TimeZone') }
        Mock Invoke-W32tm {
            $script:calls.Add('w32tm ' + ($ArgumentList -join ' '))
            switch ($ArgumentList[0]) {
                '/resync' { [pscustomobject]@{ ExitCode = $script:resyncExit; Output = '' } }
                '/query'  { [pscustomobject]@{ ExitCode = 0; Output = $(if ($ArgumentList[1] -eq '/source') { $script:sourceAfter } else { '' }) } }
                default   { [pscustomobject]@{ ExitCode = 0; Output = '' } }
            }
        }
    }

    It 'Inicia o W32Time antes de w32tm /config' {
        $r = Sync-ComputerTime -Apply

        $r.Success | Should -BeTrue
        $start = $script:calls.IndexOf('Start-Service')
        $config = @($script:calls | Where-Object { $_ -like 'w32tm /config*' })[0]
        $start | Should -BeGreaterOrEqual 0
        $start | Should -BeLessThan $script:calls.IndexOf($config)
    }

    It 'Aplica o fuso mesmo quando a sincronizacao falha' {
        $script:resyncExit = 1

        $r = Sync-ComputerTime -Apply -TimeZoneId 'E. South America Standard Time'

        $script:calls | Should -Contain 'Set-TimeZone'
        $r.Success | Should -BeFalse
        ($r.Errors -join ' ') | Should -Match 'resync'
    }

    It 'Falha quando a fonte final continua sendo o relogio local' {
        $script:sourceAfter = 'Local CMOS Clock'

        $r = Sync-ComputerTime -Apply

        $r.Success | Should -BeFalse
        ($r.Errors -join ' ') | Should -Match 'relógio local'
    }

    It '-WhatIf nao altera fonte, servico nem fuso' {
        Sync-ComputerTime -Apply -TimeZoneId 'E. South America Standard Time' -WhatIf | Out-Null

        @($script:calls | Where-Object { $_ -like 'w32tm /config*' -or $_ -in @('Start-Service', 'Set-TimeZone') }).Count | Should -Be 0
    }
}
