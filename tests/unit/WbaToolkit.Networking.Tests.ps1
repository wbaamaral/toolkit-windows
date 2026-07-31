#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $repoRoot = Get-XtudoRepoRoot
    $script:launcherContent = Get-XtudoLauncherContent
    $script:connectivityContent = Get-Content -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'testar-conectividade-internet.ps1') -Raw
    $script:hardwareContent = Get-Content -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'verificar-atualizacoes-hardware.ps1') -Raw
    $script:connectivityModuleContent = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1') -Raw
    $script:coreModuleContent = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Raw
    $script:reportHtmlContent = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Networking/Private/ConvertTo-ConnectivityReportHtml.ps1') -Raw
    $script:ipRangeContent   = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Networking/Private/ConvertFrom-IpRange.ps1') -Raw
    $script:arpSweepContent  = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Networking/Private/Invoke-ArpSweep.ps1') -Raw
    $script:duplicateReport  = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Networking/Private/New-DuplicateIpReport.ps1') -Raw
    $script:detectDuplicate  = Get-Content -LiteralPath (Join-Path $repoRoot 'modules/WbaToolkit.Networking/Public/Detect-DuplicateIp.ps1') -Raw
    $script:scriptWrapper    = Get-Content -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'detectar-ip-duplicado.ps1') -Raw

    # Dot-source direto do ConvertFrom-IpRange para testes funcionais (nao depende
    # de Windows CIM nem Get-NetNeighbor — soh aritmetica de inteiros).
    . (Join-Path $repoRoot 'modules/WbaToolkit.Networking/Private/ConvertFrom-IpRange.ps1')
    Import-Module (Join-Path $repoRoot 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1') -Force -DisableNameChecking
}

Describe 'Xtudo rotas de rede' {
    It 'Mantem os scripts oficiais de rede em scripts/' {
        Test-Path -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'testar-conectividade-internet.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'verificar-atualizacoes-hardware.ps1') | Should -BeTrue
        $script:connectivityContent | Should -Match 'modules/WbaToolkit\.Networking'
        $script:hardwareContent | Should -Match 'WbaToolkit\.Core'
        $script:connectivityModuleContent | Should -Match 'RootModule'
        $script:coreModuleContent | Should -Match 'RootModule'
    }

    It 'Nao referencia experimental nos scripts oficiais de rede' {
        $script:connectivityContent | Should -Not -Match 'experimental/'
        $script:hardwareContent | Should -Not -Match 'experimental/'
    }

    It 'Mantem atualização pesquisavel no launcher' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/atualizar-windows\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Atualizar Windows'"
        $script:launcherContent | Should -Match "Keywords\s+=\s+@\('atualizar', 'update', 'windows update', 'winget', 'chocolatey'\)"
    }
}

Describe 'ConvertTo-ConnectivityReportHtml' {
    It 'Tem uma classe Tailwind mapeada para toda Color usada nos cards de resumo' {
        # Cada Color em $cards precisa de chave correspondente em $cardColorClasses,
        # senao o card fica sem cor de fundo (silenciosamente) no HTML gerado.
        $cardColors = [regex]::Matches($script:reportHtmlContent, "Color\s*=\s*'([a-z]+)'") |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique

        $mappedColors = [regex]::Matches($script:reportHtmlContent, "(?m)^\s+([a-z]+)\s*=\s*'bg-[a-z]+-\d+'") |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique

        $cardColors.Count | Should -BeGreaterThan 0
        foreach ($color in $cardColors) {
            $mappedColors | Should -Contain $color
        }
    }
}

Describe 'ConvertFrom-IpRange (parser de faixa de IP)' {
    It 'Expande /24 em 254 enderecos uteis' {
        $ips = ConvertFrom-IpRange -Range '192.168.1.0/24'
        @($ips).Count | Should -Be 254
        $ips[0]   | Should -Be '192.168.1.1'
        $ips[-1]  | Should -Be '192.168.1.254'
    }

    It 'Expande /30 em 2 enderecos uteis' {
        $ips = ConvertFrom-IpRange -Range '10.0.0.0/30'
        @($ips).Count | Should -Be 2
        $ips -contains '10.0.0.1' | Should -BeTrue
        $ips -contains '10.0.0.2' | Should -BeTrue
        $ips -contains '10.0.0.0' | Should -BeFalse
        $ips -contains '10.0.0.3' | Should -BeFalse
    }

    It 'Expande /31 em 2 enderecos (p2p)' {
        $ips = ConvertFrom-IpRange -Range '10.0.0.0/31'
        @($ips).Count | Should -Be 2
        $ips -contains '10.0.0.0' | Should -BeTrue
        $ips -contains '10.0.0.1' | Should -BeTrue
    }

    It 'Expande /32 como endereco unico' {
        $ips = ConvertFrom-IpRange -Range '192.168.1.5/32'
        @($ips).Count | Should -Be 1
        $ips[0] | Should -Be '192.168.1.5'
    }

    It 'Expande intervalo completo (192.168.1.1-192.168.1.10)' {
        $ips = ConvertFrom-IpRange -Range '192.168.1.1-192.168.1.10'
        @($ips).Count | Should -Be 10
        $ips[0]  | Should -Be '192.168.1.1'
        $ips[-1] | Should -Be '192.168.1.10'
    }

    It 'Expande intervalo compacto (192.168.1.10-50) em 41 enderecos' {
        $ips = ConvertFrom-IpRange -Range '192.168.1.10-50'
        @($ips).Count | Should -Be 41
        $ips[0]  | Should -Be '192.168.1.10'
        $ips[-1] | Should -Be '192.168.1.50'
    }

    It 'Trata IP unico como faixa de 1' {
        $ips = ConvertFrom-IpRange -Range '10.1.1.1'
        @($ips).Count | Should -Be 1
        $ips[0] | Should -Be '10.1.1.1'
    }

    It 'Rejeita formato misto CIDR+intervalo' {
        { ConvertFrom-IpRange -Range '192.168.1.0/24-10' } | Should -Throw
    }

    It 'Rejeita mascara fora de 1..32' {
        { ConvertFrom-IpRange -Range '192.168.1.0/33' } | Should -Throw
    }

    It 'Rejeita intervalo com inicio > fim' {
        { ConvertFrom-IpRange -Range '192.168.1.10-192.168.1.5' } | Should -Throw
    }

    It 'Rejeita formato nao reconhecido' {
        { ConvertFrom-IpRange -Range 'nao-e-ip' } | Should -Throw
    }

    It 'Rejeita intervalo compacto com octeto fora de 0..255' {
        { ConvertFrom-IpRange -Range '192.168.1.10-999' } | Should -Throw
    }

    It '/23 expande em 510 enderecos uteis' {
        $ips = ConvertFrom-IpRange -Range '192.168.4.0/23'
        @($ips).Count | Should -Be 510
        $ips[0]  | Should -Be '192.168.4.1'
        $ips[-1] | Should -Be '192.168.5.254'
    }
}

Describe 'Invoke-ArpSweep (analise estatica)' {
    It 'Usa SendPingAsync para concorrencia' {
        $script:arpSweepContent | Should -Match 'SendPingAsync'
    }

    It 'Usa Get-NetNeighbor como primario se disponivel' {
        $script:arpSweepContent | Should -Match 'Get-NetNeighbor'
    }

    It 'Tem fallback para arp -a' {
        $script:arpSweepContent | Should -Match 'arp -a'
    }

    It 'Tem regex robusto que aceita separador - e : no MAC' {
        $script:arpSweepContent | Should -Match '\(\[0-9a-fA-F\]\{2\}\[-:\]\)\{5\}'
        $script:arpSweepContent | Should -Match "Replace\(':', '-'\)"
    }

    It 'Filtra apenas IPs dentro do range informado' {
        $script:arpSweepContent | Should -Match 'ipSet'
        $script:arpSweepContent | Should -Match 'Contains'
    }

    It 'Ignora MACs zero/broadcast' {
        $script:arpSweepContent | Should -Match '00-00-00-00-00-00'
        $script:arpSweepContent | Should -Match 'ff-ff-ff-ff-ff-ff'
    }

    It 'Respeita -Throttle agrupando em chunks' {
        $script:arpSweepContent | Should -Match 'chunkStart'
        $script:arpSweepContent | Should -Match 'Throttle'
    }

    It 'Nao exige Administrador (sem Test-IsAdministrator)' {
        $script:arpSweepContent | Should -Not -Match 'Test-IsAdministrator'
    }
}

Describe 'New-DuplicateIpReport (analise estatica)' {
    It 'Gera 3 arquivos: relatorio.txt, relatorio.md, relatorio.html' {
        $script:duplicateReport | Should -Match "relatorio\.txt"
        $script:duplicateReport | Should -Match "relatorio\.md"
        $script:duplicateReport | Should -Match "relatorio\.html"
    }

    It 'Usa New-ToolkitHtmlReport para HTML' {
        $script:duplicateReport | Should -Match 'New-ToolkitHtmlReport'
    }

    It 'Grava com UTF8Encoding($true) — BOM (ADR 0007)' {
        $script:duplicateReport | Should -Match 'UTF8Encoding\(\$true\)'
    }

    It 'Cria diretorio de saida se nao existir' {
        $script:duplicateReport | Should -Match 'New-Item.*Directory'
    }

    It 'Inclui timestamp no relatorio' {
        $script:duplicateReport | Should -Match 'Timestamp'
    }

    It 'Marca DUPLICADO no status' {
        $script:duplicateReport | Should -Match "DUPLICADO"
        $script:duplicateReport | Should -Match "badge-red"
    }

    It 'Inclui contagem e seção de IPs livres' {
        $script:duplicateReport | Should -Match 'totalFree'
        $script:duplicateReport | Should -Match 'IPs livres'
        $script:duplicateReport | Should -Match 'IPs Livres'
    }
}

Describe 'Detect-DuplicateIp (analise estatica)' {
    It 'Exporta Detect-DuplicateIp no psd1' {
        $script:connectivityModuleContent | Should -Match 'Detect-DuplicateIp'
    }

    It 'Delega parsing para ConvertFrom-IpRange' {
        $script:detectDuplicate | Should -Match 'ConvertFrom-IpRange'
    }

    It 'Delega varredura para Invoke-ArpSweep' {
        $script:detectDuplicate | Should -Match 'Invoke-ArpSweep'
    }

    It 'Delega relatorio para New-DuplicateIpReport' {
        $script:detectDuplicate | Should -Match 'New-DuplicateIpReport'
    }

    It 'Calcula IPs livres e ocupados a partir da faixa e do ARP' {
        $script:detectDuplicate | Should -Match 'occupiedSet'
        $script:detectDuplicate | Should -Match 'freeIps'
        $script:detectDuplicate | Should -Match 'TotalLivres'
        $script:detectDuplicate | Should -Match 'TotalOcupados'
    }

    It 'Usa Write-Verbose em vez de Write-Host direto' {
        $script:detectDuplicate | Should -Match 'Write-Verbose'
        $script:detectDuplicate | Should -Not -Match 'Write-Host\b.*-ForegroundColor'
    }

    It 'Comenta cada uma das 5 etapas principais' {
        $script:detectDuplicate | Should -Match 'ETAPA 1'
        $script:detectDuplicate | Should -Match 'ETAPA 2'
        $script:detectDuplicate | Should -Match 'ETAPA 3'
        $script:detectDuplicate | Should -Match 'ETAPA 4'
        $script:detectDuplicate | Should -Match 'ETAPA 5'
    }
}

Describe 'Detect-DuplicateIp (ocupados e livres)' {
    It 'Calcula livres sem perder duplicados na contagem de ocupados' {
        Mock Invoke-ArpSweep {
            @(
                [pscustomobject]@{ IP = '192.168.1.1'; MAC = 'aa-bb-cc-dd-ee-01' }
                [pscustomobject]@{ IP = '192.168.1.1'; MAC = 'aa-bb-cc-dd-ee-02' }
                [pscustomobject]@{ IP = '192.168.1.3'; MAC = 'aa-bb-cc-dd-ee-03' }
            )
        } -ModuleName WbaToolkit.Networking

        $outputPath = Join-Path $TestDrive 'duplicate-report'
        $result = @(Detect-DuplicateIp -Range '192.168.1.1-4' -OutputPath $outputPath -ErrorAction Stop)

        @($result).Count | Should -Be 2
        ($result | Where-Object IP -eq '192.168.1.1').Status | Should -Be 'DUPLICADO'
        $markdownPath = @($result[0].ReportFiles | Where-Object { $_ -like '*relatorio.md' })[0]
        Test-Path -LiteralPath $markdownPath | Should -BeTrue
        $markdown = Get-Content -LiteralPath $markdownPath -Raw
        $markdown | Should -Match 'IPs ocupados.*2'
        $markdown | Should -Match 'IPs livres.*2'
        $markdown | Should -Match '192\.168\.1\.2'
        $markdown | Should -Match '192\.168\.1\.4'
    }
}

Describe 'detectar-ip-duplicado.ps1 (wrapper operacional)' {
    It 'Existe em scripts/ (kebab-case ADR 0024)' {
        Test-Path -LiteralPath (Join-Path (Get-XtudoScriptsRoot) 'detectar-ip-duplicado.ps1') | Should -BeTrue
    }

    It 'Despacha -Help antes de elevacao (ADR 0021)' {
        $script:scriptWrapper | Should -Match 'if \(\$Help\) \{ Show-Help; exit 0'
    }

    It 'Adiciona modules/ ao PSModulePath (padrao-dependencias-modulos)' {
        $script:scriptWrapper | Should -Match 'PSModulePath'
    }

    It 'Carrega WbaToolkit.Core e WbaToolkit.Networking por dot-source' {
        $script:scriptWrapper | Should -Match 'modules/WbaToolkit\.Core'
        $script:scriptWrapper | Should -Match 'modules/WbaToolkit\.Networking'
        $script:scriptWrapper | Should -Match "Get-ChildItem -LiteralPath .* -Filter '\*\.ps1' -File"
        $script:scriptWrapper | Should -Match 'ForEach-Object \{ \. \$_\.FullName \}'
    }

    It 'Nao depende de opcoes legadas de Import-Module' {
        $script:scriptWrapper | Should -Not -Match 'Import-Module'
        $script:scriptWrapper | Should -Not -Match 'DisableNameChecking'
    }

    It 'Delega a sessao padronizada ao modulo' {
        $script:detectDuplicate | Should -Match 'Initialize-ToolkitReportSession'
        $script:detectDuplicate | Should -Match 'ModuleName.*detectar-ip-duplicado'
    }

    It 'Usa funcoes do Core para feedback (Write-Title/Ok/Fail/Info/Warn)' {
        $script:scriptWrapper | Should -Match 'Write-Title'
        $script:scriptWrapper | Should -Match 'Write-Ok'
        $script:scriptWrapper | Should -Match 'Write-Fail'
        $script:scriptWrapper | Should -Match 'Write-Info'
        $script:scriptWrapper | Should -Match 'Write-Warn'
    }

    It 'Tem metadados WBA-DOCS (ADR documentacao)' {
        $script:scriptWrapper | Should -Match 'WBA-DOCS:.*Category=Networking'
    }

    It 'Tem Requires Version 5.1' {
        $script:scriptWrapper | Should -Match '#Requires -Version 5\.1'
    }
}
