#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $repoRoot = Get-XtudoRepoRoot

    $script:launcherContent   = Get-XtudoLauncherContent
    $script:auditWrapper      = Get-Content -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'auditar-arquivos-dropbox.ps1') -Raw
    $script:doctorWrapper     = Get-Content -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'diagnosticar-dropbox.ps1') -Raw
    $script:maintModuleContent = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1') -Raw

    # Dot-source direto das funcoes puras (sem dependencia de outras funcoes do
    # modulo) para testes isolados, no mesmo padrao usado para ConvertFrom-IpRange
    # em WbaToolkit.Networking.Tests.ps1.
    . (Join-Path $repoRoot 'modules/WbaToolkit.Maintenance/Private/Get-DropboxProblemFileFlags.ps1')

    # Stub global para cmdlets exclusivos do Windows ausentes em pwsh no Linux
    # (padrao-testes-pester.md: "Stub global para cmdlet exclusivo do Windows").
    # Declarado ANTES do Import-Module e FORA de InModuleScope para ficar visivel
    # e mockavel em todos os blocos It subsequentes.
    if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) {
        function global:Add-MpPreference { param($ExclusionPath) }
    }

    Import-Module (Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Force -ErrorAction Stop
    Import-Module (Join-Path $repoRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1') -Force -ErrorAction Stop
}

Describe 'Rotas Dropbox no toolkit (analise estatica)' {
    It 'Mantem os dois scripts oficiais de Dropbox em scripts/' {
        Test-Path -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'auditar-arquivos-dropbox.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'diagnosticar-dropbox.ps1') | Should -BeTrue
    }

    It 'Despacham -Help antes de qualquer outra verificacao (ADR 0021)' {
        $script:auditWrapper  | Should -Match 'if \(\$Help\) \{ Show-Help; exit 0 \}'
        $script:doctorWrapper | Should -Match 'if \(\$Help\) \{ Show-Help; exit 0 \}'
    }

    It 'Adicionam modules/ ao PSModulePath (padrao-dependencias-modulos)' {
        $script:auditWrapper  | Should -Match 'PSModulePath'
        $script:doctorWrapper | Should -Match 'PSModulePath'
    }

    It 'Carregam WbaToolkit.Core e WbaToolkit.Maintenance por dot-source (ADR 0032)' {
        foreach ($content in @($script:auditWrapper, $script:doctorWrapper)) {
            $content | Should -Match 'modules/WbaToolkit\.Core'
            $content | Should -Match 'modules/WbaToolkit\.Maintenance'
            $content | Should -Match "Get-ChildItem -LiteralPath .* -Filter '\*\.ps1' -File"
            $content | Should -Match 'ForEach-Object \{ \. \$_\.FullName \}'
            $content | Should -Not -Match 'Import-Module'
            $content | Should -Not -Match 'DisableNameChecking'
        }
    }

    It 'Usam as funcoes de feedback do Core (Write-Title/Ok/Fail/Info/Warn)' {
        foreach ($content in @($script:auditWrapper, $script:doctorWrapper)) {
            $content | Should -Match 'Write-Title'
            $content | Should -Match 'Write-Ok'
            $content | Should -Match 'Write-Fail'
            $content | Should -Match 'Write-Info'
            $content | Should -Match 'Write-Warn'
        }
    }

    It 'Tem metadados WBA-DOCS' {
        $script:auditWrapper  | Should -Match 'WBA-DOCS:.*Category=Invent'
        $script:doctorWrapper | Should -Match 'WBA-DOCS:.*Category=Diagnostico'
    }

    It 'Tem Requires Version 5.1' {
        $script:auditWrapper  | Should -Match '#Requires -Version 5\.1'
        $script:doctorWrapper | Should -Match '#Requires -Version 5\.1'
    }

    It 'O .psd1 do Maintenance exporta as funcoes novas de Dropbox' {
        $script:maintModuleContent | Should -Match "'Get-DropboxInstallation'"
        $script:maintModuleContent | Should -Match "'Get-DropboxFileReport'"
        $script:maintModuleContent | Should -Match "'Invoke-DropboxHealthCheck'"
        $script:maintModuleContent | Should -Match "'Restart-DropboxProcess'"
        $script:maintModuleContent | Should -Match "'Add-DropboxDefenderExclusion'"
    }

    It 'O catalogo do xtudo.ps1 contem as duas entradas novas de Dropbox' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/diagnosticar-dropbox\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Diagnosticar Dropbox'"
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/auditar-arquivos-dropbox\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Auditoria de arquivos do Dropbox'"
        $script:launcherContent | Should -Match "Keywords\s+=\s+@\('dropbox', 'sincronizacao', 'sync', 'nuvem', 'cloud'\)"
        $script:launcherContent | Should -Match "Keywords\s+=\s+@\('dropbox', 'auditoria', 'arquivos', 'nuvem', 'cloud', 'placeholder'\)"
    }
}

Describe 'Get-DropboxProblemFileFlags' {
    It 'Detecta nome reservado do Windows' {
        $flags = Get-DropboxProblemFileFlags -Name 'CON.txt' -FullPath 'C:\Dropbox\CON.txt'
        @($flags) | Should -Not -BeNullOrEmpty
        ($flags -join ' ') | Should -Match 'reservado'
    }

    It 'Detecta nome reservado sem extensao, case-insensitive' {
        $flags = Get-DropboxProblemFileFlags -Name 'com1' -FullPath 'C:\Dropbox\com1'
        @($flags) | Should -Not -BeNullOrEmpty
    }

    It 'Detecta caractere invalido no nome' {
        $flags = Get-DropboxProblemFileFlags -Name 'relatorio|final.docx' -FullPath 'C:\Dropbox\relatorio|final.docx'
        @($flags) | Should -Not -BeNullOrEmpty
        ($flags -join ' ') | Should -Match 'invalido'
    }

    It 'Detecta nome terminado em espaco' {
        $flags = Get-DropboxProblemFileFlags -Name 'relatorio final ' -FullPath 'C:\Dropbox\relatorio final '
        @($flags) | Should -Not -BeNullOrEmpty
        ($flags -join ' ') | Should -Match 'ponto ou espaco'
    }

    It 'Detecta nome terminado em ponto' {
        $flags = Get-DropboxProblemFileFlags -Name 'relatorio.' -FullPath 'C:\Dropbox\relatorio.'
        @($flags) | Should -Not -BeNullOrEmpty
    }

    It 'Detecta caminho completo com mais de 259 caracteres' {
        $longPath = 'C:\Dropbox\' + ('a' * 260)
        $flags = Get-DropboxProblemFileFlags -Name 'a' -FullPath $longPath
        @($flags) | Should -Not -BeNullOrEmpty
        ($flags -join ' ') | Should -Match '259'
    }

    It 'Retorna array vazio para item limpo' {
        $flags = Get-DropboxProblemFileFlags -Name 'relatorio-final.docx' -FullPath 'C:\Dropbox\relatorio-final.docx'
        @($flags).Count | Should -Be 0
    }

    It 'Nao trata / ou \ do separador de caminho como caractere invalido do nome' {
        $flags = Get-DropboxProblemFileFlags -Name 'pasta-normal' -FullPath 'C:\Dropbox\pasta-normal'
        @($flags).Count | Should -Be 0
    }
}

Describe 'Get-DropboxInstallation' {
    BeforeEach {
        $script:origAppData = $env:APPDATA
        $script:origLocalAppData = $env:LOCALAPPDATA
    }

    AfterEach {
        $env:APPDATA = $script:origAppData
        $env:LOCALAPPDATA = $script:origLocalAppData
    }

    It 'Retorna vazio quando nenhum info.json existe' {
        $env:APPDATA = Join-Path $TestDrive 'sem-appdata'
        $env:LOCALAPPDATA = Join-Path $TestDrive 'sem-localappdata'

        $result = @(Get-DropboxInstallation)
        $result.Count | Should -Be 0
    }

    It 'Parseia um info.json valido e retorna a conta/caminho' {
        $appDataDir = Join-Path $TestDrive 'AppData1'
        $dropboxFolder = Join-Path $TestDrive 'DropboxFolder1'
        New-Item -Path $dropboxFolder -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $appDataDir 'Dropbox') -ItemType Directory -Force | Out-Null

        $infoJson = @{ personal = @{ path = $dropboxFolder } } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $appDataDir 'Dropbox/info.json') -Value $infoJson -Encoding UTF8

        $env:APPDATA = $appDataDir
        $env:LOCALAPPDATA = Join-Path $TestDrive 'sem-localappdata2'

        $result = @(Get-DropboxInstallation)
        $result.Count | Should -Be 1
        $result[0].Conta | Should -Be 'personal'
        $result[0].Caminho | Should -Be (Resolve-Path -LiteralPath $dropboxFolder).Path
    }

    It 'Emite aviso e continua quando um info.json esta malformado' {
        $appDataDir = Join-Path $TestDrive 'AppData2'
        $localAppDataDir = Join-Path $TestDrive 'LocalAppData2'
        $dropboxFolder = Join-Path $TestDrive 'DropboxFolder2'
        New-Item -Path $dropboxFolder -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $appDataDir 'Dropbox') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $localAppDataDir 'Dropbox') -ItemType Directory -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $appDataDir 'Dropbox/info.json') -Value '{ isto nao e json valido' -Encoding UTF8

        $infoJson = @{ business = @{ path = $dropboxFolder } } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $localAppDataDir 'Dropbox/info.json') -Value $infoJson -Encoding UTF8

        $env:APPDATA = $appDataDir
        $env:LOCALAPPDATA = $localAppDataDir

        $result = @(Get-DropboxInstallation -WarningVariable warnings -WarningAction SilentlyContinue)

        $result.Count | Should -Be 1
        $result[0].Conta | Should -Be 'business'
        @($warnings).Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-DropboxFileReport' {
    It 'Classifica arquivos comuns como LocalENuvem e preenche ProblemFlags' {
        $root = Join-Path $TestDrive 'dropbox-report-1'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'arquivo-normal.txt') -Value 'conteudo' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'CON.txt') -Value 'conteudo' -Encoding UTF8

        $report = @(Get-DropboxFileReport -Path $root -Recurse $false)

        $report.Count | Should -Be 2
        $normal = $report | Where-Object Nome -eq 'arquivo-normal.txt'
        $normal.Estado | Should -Be 'LocalENuvem'
        @($normal.ProblemFlags).Count | Should -Be 0

        $reserved = $report | Where-Object Nome -eq 'CON.txt'
        @($reserved.ProblemFlags).Count | Should -BeGreaterThan 0
    }

    It 'Nao inclui diretorios por padrao, e inclui com -IncludeDirectories' {
        $root = Join-Path $TestDrive 'dropbox-report-2'
        New-Item -Path (Join-Path $root 'subpasta') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'arquivo.txt') -Value 'x' -Encoding UTF8

        $withoutDirs = @(Get-DropboxFileReport -Path $root -Recurse $true)
        $withoutDirs.Count | Should -Be 1
        $withoutDirs[0].Tipo | Should -Be 'Arquivo'

        $withDirs = @(Get-DropboxFileReport -Path $root -Recurse $true -IncludeDirectories)
        $withDirs.Count | Should -Be 2
        @($withDirs | Where-Object Tipo -eq 'Diretorio').Count | Should -Be 1
    }

    It 'Classifica como Indeterminado quando a classificacao de um item falha' {
        $root = Join-Path $TestDrive 'dropbox-report-3'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'arquivo.txt') -Value 'x' -Encoding UTF8

        Mock Get-DropboxCloudFileState { throw 'Falha sintetica de classificacao.' } -ModuleName WbaToolkit.Maintenance

        $report = @(Get-DropboxFileReport -Path $root -Recurse $false)

        $report.Count | Should -Be 1
        $report[0].Estado | Should -Be 'Indeterminado'
        $report[0].Motivo | Should -Match 'Falha sintetica'
        @($report[0].ProblemFlags).Count | Should -Be 0
    }

    It 'Lanca erro claro quando o diretorio nao existe' {
        { Get-DropboxFileReport -Path (Join-Path $TestDrive 'nao-existe-mesmo') } | Should -Throw
    }
}

Describe 'Invoke-DropboxHealthCheck' {
    BeforeEach {
        $script:dropboxRoot = Join-Path $TestDrive "dropbox-health-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $script:dropboxRoot -ItemType Directory -Force | Out-Null

        Mock Get-DropboxInstallation {
            [pscustomobject]@{ Conta = 'personal'; Caminho = $script:dropboxRoot; InfoJson = 'info.json' }
        } -ModuleName WbaToolkit.Maintenance

        Mock Get-DropboxFileReport { @() } -ModuleName WbaToolkit.Maintenance
        Mock Test-DropboxTcpPort { $true } -ModuleName WbaToolkit.Maintenance
        Mock Get-DropboxProxyConfiguration {
            [pscustomobject]@{ ExitCode = 0; Output = 'Direct access (no proxy server).' }
        } -ModuleName WbaToolkit.Maintenance
        Mock Get-DropboxDefenderPreference {
            [pscustomobject]@{ ExclusionPath = @($script:dropboxRoot) }
        } -ModuleName WbaToolkit.Maintenance
        Mock Get-DropboxTimeSyncStatus {
            [pscustomobject]@{ ExitCode = 0; Output = 'Leap Indicator: 0(no leap second)|Last Successful Sync Time: 8/17/2026 10:00:00 AM' }
        } -ModuleName WbaToolkit.Maintenance
        Mock Get-DropboxDiskFreeInfo {
            [pscustomobject]@{ Size = 100GB; FreeSpace = 50GB }
        } -ModuleName WbaToolkit.Maintenance
        Mock Get-DropboxProcessInfo {
            [pscustomobject]@{ Name = 'Dropbox'; Path = 'C:\Fake\Dropbox.exe' }
        } -ModuleName WbaToolkit.Maintenance
    }

    It 'Retorna Score 100 e Label Excelente em cenario 100% saudavel' {
        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        $result.Score | Should -Be 100
        $result.Label | Should -Be 'Excelente'
        $result.CriticalCount | Should -Be 0
        $result.WarningCount | Should -Be 0
        $result.Path | Should -Be $script:dropboxRoot

        Should -Invoke Test-DropboxTcpPort -ModuleName WbaToolkit.Maintenance
        Should -Invoke Get-DropboxProcessInfo -ModuleName WbaToolkit.Maintenance
    }

    It 'Marca Label Critico quando o processo Dropbox nao esta em execucao' {
        Mock Get-DropboxProcessInfo { } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        $result.Label | Should -Be 'Critico'
        $result.CriticalCount | Should -Be 1
        $result.Score | Should -Be 60
    }

    It 'Marca Label Bom/Degradado quando ha apenas avisos (Defender e proxy)' {
        Mock Get-DropboxDefenderPreference { [pscustomobject]@{ ExclusionPath = @() } } -ModuleName WbaToolkit.Maintenance
        Mock Get-DropboxProxyConfiguration {
            [pscustomobject]@{ ExitCode = 0; Output = 'Servidor proxy(http): 10.0.0.1:8080' }
        } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        $result.CriticalCount | Should -Be 0
        $result.WarningCount | Should -Be 2
        $result.Score | Should -Be 90
        $result.Label | Should -Be 'Bom'
    }

    It 'Lanca erro orientando -Path quando a instalacao nao pode ser resolvida sozinha' {
        Mock Get-DropboxInstallation { } -ModuleName WbaToolkit.Maintenance

        { Invoke-DropboxHealthCheck } | Should -Throw '*-Path*'
    }

    It 'Emite AVISO quando ha multiplas instancias do processo Dropbox' {
        Mock Get-DropboxProcessInfo {
            @(
                [pscustomobject]@{ Name = 'Dropbox'; Path = 'C:\Fake\Dropbox.exe' }
                [pscustomobject]@{ Name = 'Dropbox'; Path = 'C:\Fake\Dropbox.exe' }
            )
        } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        $result.CriticalCount | Should -Be 0
        $result.WarningCount | Should -Be 1
        ($result.Checks | Where-Object Nome -eq 'Processo dropbox.exe').Status | Should -Be 'AVISO'
    }

    It 'Marca FALHA critica quando o caminho informado nao existe' {
        $result = Invoke-DropboxHealthCheck -Path (Join-Path $TestDrive 'nao-existe-mesmo-assim')

        $result.CriticalCount | Should -Be 1
        $result.Label | Should -Be 'Critico'
        ($result.Checks | Where-Object Nome -eq 'Pasta Dropbox').Status | Should -Be 'FALHA'
    }

    It 'Emite AVISO de instalacao quando a pasta existe mas nenhuma conta foi confirmada' {
        Mock Get-DropboxInstallation { } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Conta Dropbox').Status | Should -Be 'AVISO'
    }

    It 'Emite AVISO de espaco livre entre 5% e 10%' {
        Mock Get-DropboxDiskFreeInfo { [pscustomobject]@{ Size = 100GB; FreeSpace = 8GB } } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Espaco livre').Status | Should -Be 'AVISO'
    }

    It 'Marca FALHA critica quando o espaco livre esta abaixo de 5% ou 1GB' {
        Mock Get-DropboxDiskFreeInfo { [pscustomobject]@{ Size = 100GB; FreeSpace = 500MB } } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Espaco livre').Status | Should -Be 'FALHA'
        $result.CriticalCount | Should -Be 1
    }

    It 'Emite AVISO quando ha arquivos com nome/caminho problematico' {
        Mock Get-DropboxFileReport {
            @(
                [pscustomobject]@{ Nome = 'CON.txt'; Caminho = 'C:\Dropbox\CON.txt'; ProblemFlags = @('Nome reservado.') }
            )
        } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        $check = $result.Checks | Where-Object Nome -eq 'Nomes/caminhos problematicos'
        $check.Status | Should -Be 'AVISO'
        $check.Detalhe | Should -Match 'CON\.txt'
    }

    It 'Avalia pastas criticas: ausente, vazia, desatualizada e atualizada' {
        $freshFolder = Join-Path $script:dropboxRoot 'Fresca'
        $staleFolder = Join-Path $script:dropboxRoot 'Antiga'
        $emptyFolder = Join-Path $script:dropboxRoot 'Vazia'
        New-Item -Path $freshFolder -ItemType Directory -Force | Out-Null
        New-Item -Path $staleFolder -ItemType Directory -Force | Out-Null
        New-Item -Path $emptyFolder -ItemType Directory -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $freshFolder 'novo.txt') -Value 'x' -Encoding UTF8

        $staleFile = Join-Path $staleFolder 'antigo.txt'
        Set-Content -LiteralPath $staleFile -Value 'x' -Encoding UTF8
        (Get-Item -LiteralPath $staleFile).LastWriteTime = (Get-Date).AddDays(-10)

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot -CriticalFolders @('Fresca', 'Antiga', 'Vazia', 'Ausente') -FreshnessDays 2

        ($result.Checks | Where-Object Nome -eq 'Pasta critica: Fresca').Status   | Should -Be 'OK'
        ($result.Checks | Where-Object Nome -eq 'Pasta critica: Antiga').Status   | Should -Be 'AVISO'
        ($result.Checks | Where-Object Nome -eq 'Pasta critica: Vazia').Status    | Should -Be 'AVISO'
        ($result.Checks | Where-Object Nome -eq 'Pasta critica: Ausente').Status  | Should -Be 'AVISO'
    }

    It 'Marca FALHA critica quando todos os destinos de conectividade falham' {
        Mock Test-DropboxTcpPort { $false } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Conectividade Dropbox (TCP 443)').Status | Should -Be 'FALHA'
        $result.CriticalCount | Should -Be 1
    }

    It 'Emite AVISO de conectividade quando apenas alguns destinos falham' {
        $script:callCount = 0
        Mock Test-DropboxTcpPort {
            $script:callCount++
            return ($script:callCount -ne 1)
        } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Conectividade Dropbox (TCP 443)').Status | Should -Be 'AVISO'
    }

    It 'Emite AVISO de proxy quando a configuracao nao pode ser determinada' {
        Mock Get-DropboxProxyConfiguration { [pscustomobject]@{ ExitCode = 1; Output = '' } } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Proxy do sistema').Status | Should -Be 'AVISO'
    }

    It 'Emite AVISO de hora do sistema quando o servico nao responde' {
        Mock Get-DropboxTimeSyncStatus { [pscustomobject]@{ ExitCode = 1; Output = '' } } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Hora do sistema').Status | Should -Be 'AVISO'
    }

    It 'Emite AVISO de hora do sistema quando nunca houve sincronizacao bem-sucedida' {
        Mock Get-DropboxTimeSyncStatus {
            [pscustomobject]@{ ExitCode = 0; Output = 'Last Successful Sync Time: unspecified' }
        } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Hora do sistema').Status | Should -Be 'AVISO'
    }

    It 'Emite AVISO de Defender quando a preferencia nao pode ser consultada' {
        Mock Get-DropboxDefenderPreference { } -ModuleName WbaToolkit.Maintenance

        $result = Invoke-DropboxHealthCheck -Path $script:dropboxRoot

        ($result.Checks | Where-Object Nome -eq 'Exclusao no Defender').Status | Should -Be 'AVISO'
    }
}

Describe 'Restart-DropboxProcess' {
    It 'Informa que nao ha nada a reiniciar quando o processo nao esta em execucao' {
        Mock Get-Process { throw 'Cannot find a process with the name "Dropbox".' } -ModuleName WbaToolkit.Maintenance
        Mock Stop-Process { } -ModuleName WbaToolkit.Maintenance
        Mock Start-Process { } -ModuleName WbaToolkit.Maintenance

        $result = Restart-DropboxProcess

        $result.Success | Should -BeTrue
        $result.Restarted | Should -BeFalse
        Should -Invoke Stop-Process -ModuleName WbaToolkit.Maintenance -Times 0
    }

    It 'Para e reinicia o processo quando o executavel pode ser localizado' {
        $fakeExe = Join-Path $TestDrive 'Dropbox.exe'
        Set-Content -LiteralPath $fakeExe -Value 'fake-binary' -Encoding UTF8

        Mock Get-Process { [pscustomobject]@{ Name = 'Dropbox'; Path = $fakeExe } } -ModuleName WbaToolkit.Maintenance
        Mock Stop-Process { } -ModuleName WbaToolkit.Maintenance
        Mock Start-Process { } -ModuleName WbaToolkit.Maintenance

        $result = Restart-DropboxProcess

        $result.Success | Should -BeTrue
        $result.Restarted | Should -BeTrue
        Should -Invoke Stop-Process -ModuleName WbaToolkit.Maintenance -Times 1 -ParameterFilter { $Name -eq 'Dropbox' }
        Should -Invoke Start-Process -ModuleName WbaToolkit.Maintenance -Times 1 -ParameterFilter { $FilePath -eq $fakeExe }
    }

    It 'Reporta falha sem lancar quando Stop-Process falha' {
        Mock Get-Process { [pscustomobject]@{ Name = 'Dropbox'; Path = 'C:\Fake\Dropbox.exe' } } -ModuleName WbaToolkit.Maintenance
        Mock Stop-Process { throw 'Acesso negado' } -ModuleName WbaToolkit.Maintenance
        Mock Start-Process { } -ModuleName WbaToolkit.Maintenance

        $result = Restart-DropboxProcess

        $result.Success | Should -BeFalse
        Should -Invoke Start-Process -ModuleName WbaToolkit.Maintenance -Times 0
    }

    It 'Reporta falha quando o executavel nao pode ser localizado apos parar o processo' {
        Mock Get-Process { [pscustomobject]@{ Name = 'Dropbox'; Path = (Join-Path $TestDrive 'nao-existe.exe') } } -ModuleName WbaToolkit.Maintenance
        Mock Stop-Process { } -ModuleName WbaToolkit.Maintenance
        Mock Start-Process { } -ModuleName WbaToolkit.Maintenance

        $result = Restart-DropboxProcess

        $result.Success | Should -BeFalse
        $result.Restarted | Should -BeFalse
        $result.Message | Should -Match 'localizado'
        Should -Invoke Start-Process -ModuleName WbaToolkit.Maintenance -Times 0
    }
}

Describe 'Add-DropboxDefenderExclusion' {
    It 'Adiciona a exclusao com sucesso' {
        Mock Add-MpPreference { } -ModuleName WbaToolkit.Maintenance

        $result = Add-DropboxDefenderExclusion -Path @('C:\Users\usuario\Dropbox')

        $result.Success | Should -BeTrue
        Should -Invoke Add-MpPreference -ModuleName WbaToolkit.Maintenance -Times 1 -ParameterFilter {
            $ExclusionPath -contains 'C:\Users\usuario\Dropbox'
        }
    }

    It 'Reporta falha sem lancar quando Add-MpPreference falha (Defender ausente/negado)' {
        Mock Add-MpPreference { throw 'Add-MpPreference nao esta disponivel.' } -ModuleName WbaToolkit.Maintenance

        $result = Add-DropboxDefenderExclusion -Path @('C:\Users\usuario\Dropbox')

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'Defender'
    }
}

Describe 'Fronteiras externas isoladas (chamada direta, sem mock)' {
    # Estas funcoes ja tem seu comportamento coberto indiretamente (via mock) pelos
    # testes de Invoke-DropboxHealthCheck acima. Aqui elas sao chamadas de verdade,
    # sem mock, para exercitar o corpo real de cada uma (o cmdlet Windows-only
    # subjacente pode nao existir neste ambiente de conveniencia em pwsh/Linux --
    # nesse caso, a propria funcao trata a ausencia via try/catch e retorna $null,
    # que e exatamente o comportamento validado aqui).
    # InModuleScope precisa do modulo ja importado. O Import-Module roda dentro do
    # BeforeAll (fase de execucao); por isso cada It abre seu proprio InModuleScope
    # em vez de um unico InModuleScope envolvendo todo o bloco (que exigiria o
    # modulo carregado ja na fase de descoberta e falharia com "No modules named...").
    It 'Get-DropboxProcessInfo nao lanca mesmo sem o processo em execucao' {
        InModuleScope WbaToolkit.Maintenance {
            { Get-DropboxProcessInfo } | Should -Not -Throw
        }
    }

    It 'Get-DropboxDiskFreeInfo nao lanca para uma unidade inexistente' {
        InModuleScope WbaToolkit.Maintenance {
            { Get-DropboxDiskFreeInfo -DriveLetter 'ZZ:' } | Should -Not -Throw
        }
    }

    It 'Get-DropboxDefenderPreference nao lanca quando o cmdlet esta indisponivel ou falha' {
        InModuleScope WbaToolkit.Maintenance {
            { Get-DropboxDefenderPreference } | Should -Not -Throw
        }
    }

    It 'Get-DropboxProxyConfiguration nao lanca mesmo se netsh estiver ausente' {
        InModuleScope WbaToolkit.Maintenance {
            { Get-DropboxProxyConfiguration } | Should -Not -Throw
        }
    }

    It 'Get-DropboxTimeSyncStatus nao lanca mesmo se w32tm estiver ausente' {
        InModuleScope WbaToolkit.Maintenance {
            { Get-DropboxTimeSyncStatus } | Should -Not -Throw
        }
    }

    It 'Test-DropboxTcpPort retorna $false para host invalido' {
        InModuleScope WbaToolkit.Maintenance {
            Test-DropboxTcpPort -HostName 'host-invalido.invalido.test' -Port 443 -TimeoutMs 500 | Should -BeFalse
        }
    }

    It 'Test-DropboxTcpPort retorna $true para uma porta local aberta' {
        InModuleScope WbaToolkit.Maintenance {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            try {
                $port = $listener.LocalEndpoint.Port
                Test-DropboxTcpPort -HostName '127.0.0.1' -Port $port -TimeoutMs 2000 | Should -BeTrue
            }
            finally {
                $listener.Stop()
            }
        }
    }

    It 'New-DropboxDoctorHtmlReport monta o HTML com cards e tabela de checagens' {
        InModuleScope WbaToolkit.Maintenance {
            $checks = @(
                [pscustomobject]@{ Categoria = 'Processo'; Nome = 'Processo dropbox.exe'; Status = 'OK'; Detalhe = 'Rodando.'; Recomendacao = '' }
                [pscustomobject]@{ Categoria = 'Rede'; Nome = 'Conectividade'; Status = 'FALHA'; Detalhe = 'Sem rede.'; Recomendacao = 'Verifique firewall.' }
            )

            $html = New-DropboxDoctorHtmlReport -DropboxPath 'C:\Dropbox' -Score 80 -Label 'Bom' -CriticalCount 0 -WarningCount 1 -Checks $checks

            $html | Should -Match '<html'
            $html | Should -Match 'Diagnostico do Cliente Dropbox'
            $html | Should -Match 'badge-green'
            $html | Should -Match 'badge-red'
            $html | Should -Match 'Processo dropbox.exe'
        }
    }
}
