#requires -version 5.1

# BCK-069: cobertura das funcoes publicas do WbaToolkit.Networking que nao tinham teste.
# Nenhum teste sai para a rede: os casos de socket usam servidores locais em loopback
# (TCP, UDP e um HTTP minimo) e o navegador do PDF e um script falso no TestDrive.
# O modulo roda com Set-StrictMode -Version Latest: os objetos simulados trazem todas
# as propriedades que as funcoes leem.

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1') -Force -DisableNameChecking

    function New-TestResult {
        param([string]$Classification = 'Success', [string]$TestName = 'Teste', [object]$Port = $null)
        [pscustomobject]@{
            Classification = $Classification; TestName = $TestName; Target = '10.0.0.1'; Status = 'x'
            Port = $Port; LatencyMs = $null; ErrorMessage = $null; Recommendation = $null
        }
    }
}

Describe 'New-ConnectivityTestPlan (BCK-069)' {
    It 'Usa os alvos e a porta padrao' {
        $plan = New-ConnectivityTestPlan

        @($plan.IpTargets).Count | Should -Be 4
        $plan.IpTargets | Should -Contain '1.1.1.1'
        $plan.TcpPort | Should -Be 443
        $plan.Detailed | Should -BeFalse
    }

    It 'Aceita alvos, porta e detalhamento informados' {
        $plan = New-ConnectivityTestPlan -IpTargets '10.0.0.1' -DnsTargets 'intranet' -DomainTargets 'srv' -TcpPort 80 -Detailed

        @($plan.IpTargets) | Should -Be @('10.0.0.1')
        @($plan.DnsTargets) | Should -Be @('intranet')
        $plan.TcpPort | Should -Be 80
        $plan.Detailed | Should -BeTrue
    }

    It 'Recusa porta fora do intervalo' {
        { New-ConnectivityTestPlan -TcpPort 70000 } | Should -Throw
    }
}

Describe 'Invoke-TargetConnectivityTest (BCK-069)' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.Networking Get-NetworkContext { [pscustomobject]@{ Hostname = 'PC-TESTE' } }
        Mock -ModuleName WbaToolkit.Networking Test-IcmpConnectivity { New-TestResult -Classification 'Success' -TestName 'ICMP' }
        Mock -ModuleName WbaToolkit.Networking Test-TcpPortConnectivity { New-TestResult -Classification 'Failed' -TestName 'TCP' -Port $Port }
        Mock -ModuleName WbaToolkit.Networking Test-UdpPortConnectivity { New-TestResult -Classification 'Inconclusive' -TestName 'UDP' -Port $Port }
    }

    It 'Exige PortSpec para TCP' {
        { Invoke-TargetConnectivityTest -TargetAddress '10.0.0.9' -Protocol TCP } | Should -Throw '*PortSpec e obrigatorio*'
    }

    It 'All executa ICMP uma vez e TCP e UDP para cada porta, com resumo' {
        $r = Invoke-TargetConnectivityTest -TargetAddress '10.0.0.9' -Protocol All -PortSpec '443,80'

        @($r.Ports) -join ',' | Should -Be '80,443'
        Should -Invoke -ModuleName WbaToolkit.Networking Test-IcmpConnectivity -Times 1 -Exactly
        Should -Invoke -ModuleName WbaToolkit.Networking Test-TcpPortConnectivity -Times 2 -Exactly
        Should -Invoke -ModuleName WbaToolkit.Networking Test-UdpPortConnectivity -Times 2 -Exactly
        $r.Summary.Total | Should -Be 5
        $r.Summary.Success | Should -Be 1
        $r.Summary.Failed | Should -Be 2
        $r.Summary.Inconclusive | Should -Be 2
        $r.ReportType | Should -Be 'TargetConnectivity'
        $r.Context.Hostname | Should -Be 'PC-TESTE'
    }

    It 'ICMP dispensa PortSpec e nao testa portas' {
        $r = Invoke-TargetConnectivityTest -TargetAddress '10.0.0.9' -Protocol ICMP

        @($r.Results).Count | Should -Be 1
        Should -Invoke -ModuleName WbaToolkit.Networking Test-TcpPortConnectivity -Times 0 -Exactly
    }

    It 'Recusa range que passa do limite de portas' {
        { Invoke-TargetConnectivityTest -TargetAddress '10.0.0.9' -Protocol TCP -PortSpec '1-100' -MaxPorts 10 } | Should -Throw '*limite*'
    }
}

Describe 'Test-LocalTcpListener e Test-LocalUdpListener (BCK-069)' {
    It 'Encontra um listener TCP local e deixa de encontrar quando ele fecha' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        try {
            $aberto = Test-LocalTcpListener -Port $port
        } finally { $listener.Stop() }
        $fechado = Test-LocalTcpListener -Port $port

        $aberto.Success | Should -BeTrue
        $aberto.Status | Should -Be 'Escutando'
        $aberto.Protocol | Should -Be 'TCP'
        $fechado.Success | Should -BeFalse
        $fechado.Classification | Should -Be 'Failed'
    }

    It 'Encontra um endpoint UDP local' {
        $udp = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, 0))
        $port = $udp.Client.LocalEndPoint.Port
        try {
            $r = Test-LocalUdpListener -Port $port
        } finally { $udp.Close() }

        $r.Success | Should -BeTrue
        $r.Status | Should -Be 'Ativo'
        $r.Protocol | Should -Be 'UDP'
    }
}

Describe 'Test-UdpPortConnectivity (BCK-069)' {
    It 'Classifica como Aberta quando o destino responde' {
        $udp = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, 0))
        $port = $udp.Client.LocalEndPoint.Port
        $eco = [powershell]::Create().AddScript({
            param($u)
            $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $dados = $u.Receive([ref]$ep)
            [void]$u.Send($dados, $dados.Length, $ep)
        }).AddArgument($udp)
        $handle = $eco.BeginInvoke()
        try {
            $r = Test-UdpPortConnectivity -TargetAddress '127.0.0.1' -Port $port -TimeoutSeconds 5
        } finally {
            $udp.Close(); $eco.Stop(); $eco.Dispose()
        }

        $r.Status | Should -Be 'Aberta'
        $r.Classification | Should -Be 'Success'
    }

    It 'Classifica como Sem resposta (inconclusivo) quando o destino recebe e nao responde' {
        $udp = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, 0))
        $port = $udp.Client.LocalEndPoint.Port
        try {
            $r = Test-UdpPortConnectivity -TargetAddress '127.0.0.1' -Port $port -TimeoutSeconds 1
        } finally { $udp.Close() }

        $r.Status | Should -Be 'Sem resposta'
        $r.Classification | Should -Be 'Inconclusive'
    }

    It 'Classifica como Fechada quando o destino devolve ICMP porta inalcancavel' {
        $udp = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, 0))
        $port = $udp.Client.LocalEndPoint.Port
        $udp.Close()

        $r = Test-UdpPortConnectivity -TargetAddress '127.0.0.1' -Port $port -TimeoutSeconds 2

        $r.Status | Should -Be 'Fechada'
        $r.Classification | Should -Be 'Failed'
        $r.Port | Should -Be $port
    }
}

Describe 'Test-DownloadSpeed (BCK-069)' {
    It 'Mede o download de um servidor HTTP local' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        $servidor = [powershell]::Create().AddScript({
            param($l)
            $cliente = $l.AcceptTcpClient()
            $rede = $cliente.GetStream()
            $leitura = New-Object byte[] 4096
            [void]$rede.Read($leitura, 0, $leitura.Length)
            $corpo = New-Object byte[] (2MB)
            $cabecalho = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: $($corpo.Length)`r`nConnection: close`r`n`r`n")
            $rede.Write($cabecalho, 0, $cabecalho.Length)
            $rede.Write($corpo, 0, $corpo.Length)
            $rede.Flush()
            $cliente.Close()
        }).AddArgument($listener)
        $handle = $servidor.BeginInvoke()
        try {
            $r = Test-DownloadSpeed -Url "http://127.0.0.1:$port/arquivo" -TimeoutSeconds 10
        } finally {
            $listener.Stop(); $servidor.Stop(); $servidor.Dispose()
        }

        $r.Status | Should -Be 'OK'
        $r.TotalMB | Should -Be 2
        $r.Message | Should -Match '^Download: 2 MB'
    }

    It 'Devolve Erro quando o servidor nao existe' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()

        $r = Test-DownloadSpeed -Url "http://127.0.0.1:$port/arquivo" -TimeoutSeconds 5

        $r.Status | Should -Be 'Erro'
        $r.Message | Should -Match '^Falha no teste'
        $r.SpeedMbps | Should -Be 0
    }
}

Describe 'Show-ConnectivityReport (BCK-069)' {
    BeforeEach {
        $script:linhas = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName WbaToolkit.Networking Write-Host { $script:linhas.Add([string]$Object) }
        $script:report = [pscustomobject]@{
            FinishedAt  = Get-Date '2026-11-27 10:00:00'
            Context     = [pscustomobject]@{
                Hostname = 'PC-TESTE'; Username = 'operador'; InterfaceAlias = 'Ethernet'
                IPv4Address = '10.0.0.5'; PrefixLength = 24; Gateway = '10.0.0.1'; DnsServers = @('1.1.1.1', '8.8.8.8')
            }
            Summary     = [pscustomobject]@{ Total = 2; Success = 1; Failed = 1; Warning = 0; Inconclusive = 0; Error = 0; Skipped = 0 }
            Blocked     = $true
            BlockReason = 'Proxy sem autenticacao'
            Results     = @(
                [pscustomobject]@{ Classification = 'Success'; TestName = 'Teste TCP'; Target = '10.0.0.1'; Status = 'Aberta'; Port = 443; LatencyMs = 12.5; ErrorMessage = $null; Recommendation = 'Tudo certo.' }
                [pscustomobject]@{ Classification = 'Failed'; TestName = 'DNS'; Target = $null; Status = 'Falha'; Port = $null; LatencyMs = $null; ErrorMessage = 'timeout'; Recommendation = $null }
            )
        }
    }

    It 'Mostra contexto, resumo, bloqueio e cada resultado' {
        Show-ConnectivityReport -Report $script:report

        $texto = $script:linhas -join "`n"
        $texto | Should -Match 'Computador: PC-TESTE'
        $texto | Should -Match 'DNS:\s+1\.1\.1\.1, 8\.8\.8\.8'
        $texto | Should -Match 'Total\s+: 2'
        $texto | Should -Match 'BLOQUEADO: Proxy sem autenticacao'
        $texto | Should -Match '\[Success\] Teste TCP'
        $texto | Should -Match 'Porta\s+: 443'
        $texto | Should -Match 'Destino: -'
        $texto | Should -Match 'Erro\s+: timeout'
    }

    It 'Omite as linhas de erros e ignorados quando sao zero' {
        Show-ConnectivityReport -Report $script:report

        ($script:linhas -join "`n") | Should -Not -Match 'Erros\s+:|Ignorados\s+:'
    }
}

Describe 'Export-ConnectivityReport (BCK-069)' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.Networking ConvertTo-ConnectivityReportHtml { '<html>relatorio de teste</html>' }
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
        $script:report = [pscustomobject]@{ ReportId = 'abc123' }
    }

    It 'Com -Path de diretorio grava relatorio-conectividade-<id>.html dentro dele' {
        $r = Export-ConnectivityReport -Report $script:report -Path $script:dir

        $r.Success | Should -BeTrue
        $r.Type | Should -Be 'HTML'
        $r.Path | Should -Be (Join-Path $script:dir 'relatorio-conectividade-abc123.html')
        Get-Content -LiteralPath $r.Path -Raw | Should -Match 'relatorio de teste'
    }

    It 'Com -OutputPath cria a sessao em Networking dentro da raiz informada' {
        $r = Export-ConnectivityReport -Report $script:report -OutputPath $script:dir

        $r.Path | Should -BeLike "$($script:dir)*Networking*"
        Test-Path -LiteralPath $r.Path | Should -BeTrue
    }

    It 'Informa o caminho quando nao consegue gravar' {
        Mock -ModuleName WbaToolkit.Networking Write-TextFileUtf8 { throw 'disco cheio' }

        { Export-ConnectivityReport -Report $script:report -Path (Join-Path $script:dir 'r.html') } |
            Should -Throw '*Nao foi possivel gravar o relatorio HTML*disco cheio*'
    }
}

Describe 'Export-ConnectivityReportPdf (BCK-069)' {
    BeforeAll {
        # Navegador falso: grava o PDF, sai sem gravar ou falha, conforme a variavel de ambiente.
        $script:fakeBrowser = Join-Path $TestDrive 'navegador-falso.ps1'
        Set-Content -LiteralPath $script:fakeBrowser -Encoding UTF8 -Value @'
$pdf = (@($args) | Where-Object { $_ -like '--print-to-pdf=*' } | Select-Object -First 1) -replace '^--print-to-pdf=', ''
switch ($env:WBA_TESTE_NAVEGADOR) {
    'gera'  { Set-Content -LiteralPath $pdf -Value '%PDF-1.4 teste' }
    'falha' { throw 'navegador quebrou' }
    default { }
}
'@
    }

    BeforeEach {
        $script:html = Join-Path $TestDrive 'relatorio.html'
        Set-Content -LiteralPath $script:html -Value '<html></html>'
        $script:pdf = [System.IO.Path]::ChangeExtension($script:html, '.pdf')
        Remove-Item -LiteralPath $script:pdf -ErrorAction SilentlyContinue
        Mock -ModuleName WbaToolkit.Networking Get-Command { [pscustomobject]@{ Path = $script:fakeBrowser; Source = $script:fakeBrowser } } -ParameterFilter { $Name -eq 'msedge' }
    }

    AfterEach { Remove-Item Env:\WBA_TESTE_NAVEGADOR -ErrorAction SilentlyContinue }

    It 'Gera o PDF ao lado do HTML quando o navegador produz o arquivo' {
        $env:WBA_TESTE_NAVEGADOR = 'gera'

        $r = Export-ConnectivityReportPdf -HtmlPath $script:html

        $r.Success | Should -BeTrue
        $r.Path | Should -Be $script:pdf
        Test-Path -LiteralPath $script:pdf | Should -BeTrue
    }

    It 'Nao reporta sucesso quando o navegador sai sem gerar o PDF' {
        $env:WBA_TESTE_NAVEGADOR = 'nada'

        $r = Export-ConnectivityReportPdf -HtmlPath $script:html

        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'nao foi gerado'
    }

    It 'Devolve a falha do navegador sem lancar excecao' {
        $env:WBA_TESTE_NAVEGADOR = 'falha'

        $r = Export-ConnectivityReportPdf -HtmlPath $script:html

        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'navegador quebrou'
    }

    It 'Avisa quando nao ha navegador compativel' {
        # Com filtro, para ter prioridade sobre o mock do navegador falso do BeforeEach.
        Mock -ModuleName WbaToolkit.Networking Get-Command { $null } -ParameterFilter { $true }
        $vazio = Join-Path $TestDrive 'sem-navegador'
        New-Item -ItemType Directory -Path $vazio -Force | Out-Null
        $antes = @{ PF = $env:ProgramFiles; PF86 = ${env:ProgramFiles(x86)}; LAD = $env:LOCALAPPDATA }
        try {
            $env:ProgramFiles = $vazio; ${env:ProgramFiles(x86)} = $vazio; $env:LOCALAPPDATA = $vazio
            $r = Export-ConnectivityReportPdf -HtmlPath $script:html
        } finally {
            $env:ProgramFiles = $antes.PF; ${env:ProgramFiles(x86)} = $antes.PF86; $env:LOCALAPPDATA = $antes.LAD
        }

        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'Nenhum navegador'
    }
}

Describe 'Invoke-ConnectivityWizard (BCK-069)' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.Networking Write-Host { }
        Mock -ModuleName WbaToolkit.Networking Invoke-ConnectivityTest { [pscustomobject]@{ ReportId = 'r1' } }
        Mock -ModuleName WbaToolkit.Networking Show-ConnectivityReport { }
    }

    It 'Opcao 1 executa o teste completo, exibe e devolve o relatorio' {
        Mock -ModuleName WbaToolkit.Networking Read-Host { '1' }

        $r = Invoke-ConnectivityWizard

        $r.ReportId | Should -Be 'r1'
        Should -Invoke -ModuleName WbaToolkit.Networking Show-ConnectivityReport -Times 1 -Exactly
    }

    It 'Outra opcao cancela sem executar teste' {
        Mock -ModuleName WbaToolkit.Networking Read-Host { '2' }
        Mock -ModuleName WbaToolkit.Networking Write-Warn { }

        $r = Invoke-ConnectivityWizard

        $r | Should -BeNullOrEmpty
        Should -Invoke -ModuleName WbaToolkit.Networking Invoke-ConnectivityTest -Times 0 -Exactly
        Should -Invoke -ModuleName WbaToolkit.Networking Write-Warn -Times 1 -Exactly
    }
}

Describe 'Invoke-TargetConnectivityWizard (BCK-069)' {
    BeforeEach {
        $script:respostas = [System.Collections.Generic.Queue[string]]::new()
        Mock -ModuleName WbaToolkit.Networking Read-Host { $script:respostas.Dequeue() }
        Mock -ModuleName WbaToolkit.Networking Write-Host { }
        Mock -ModuleName WbaToolkit.Networking Show-ConnectivityReport { }
        Mock -ModuleName WbaToolkit.Networking Invoke-TargetConnectivityTest {
            [pscustomobject]@{
                StartedAt = Get-Date
                Ports     = @($(if ($PortSpec) { [int]$PortSpec } else { @() }))
                Context   = [pscustomobject]@{ Hostname = 'PC-TESTE' }
                Results   = @([pscustomobject]@{ Classification = 'Success'; TestName = "T-$Protocol" })
            }
        }
    }

    It 'Repete perguntas invalidas e consolida os protocolos escolhidos' {
        '', '10.0.0.9', '9', 'tcp, icmp', '', '443' | ForEach-Object { $script:respostas.Enqueue($_) }

        $r = Invoke-TargetConnectivityWizard

        $r.Target | Should -Be '10.0.0.9'
        $r.Protocol | Should -Be 'TCP,ICMP'
        $r.PortSpec | Should -Be '443'
        $r.Summary.Total | Should -Be 2
        Should -Invoke -ModuleName WbaToolkit.Networking Invoke-TargetConnectivityTest -Times 1 -Exactly -ParameterFilter { $Protocol -eq 'TCP' -and $PortSpec -eq '443' }
        Should -Invoke -ModuleName WbaToolkit.Networking Invoke-TargetConnectivityTest -Times 1 -Exactly -ParameterFilter { $Protocol -eq 'ICMP' }
        Should -Invoke -ModuleName WbaToolkit.Networking Show-ConnectivityReport -Times 1 -Exactly
    }

    It 'Todos vira All e testa os tres protocolos' {
        'srv01', 'todos', '80' | ForEach-Object { $script:respostas.Enqueue($_) }

        $r = Invoke-TargetConnectivityWizard

        $r.Protocol | Should -Be 'All'
        Should -Invoke -ModuleName WbaToolkit.Networking Invoke-TargetConnectivityTest -Times 3 -Exactly
    }

    It 'So ICMP nao pergunta porta' {
        'srv01', '3' | ForEach-Object { $script:respostas.Enqueue($_) }

        $r = Invoke-TargetConnectivityWizard

        $r.Protocol | Should -Be 'ICMP'
        $r.PortSpec | Should -BeNullOrEmpty
        Should -Invoke -ModuleName WbaToolkit.Networking Read-Host -Times 2 -Exactly
    }
}
