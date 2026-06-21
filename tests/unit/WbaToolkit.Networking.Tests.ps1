# Projeto: wba-toolkit
# Autor: wbaamaral

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $repoRoot 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1'

    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'WbaToolkit.Networking' {
    Context 'Exportacao do modulo' {
        It 'Deve exportar Get-NetworkContext' {
            (Get-Command Get-NetworkContext -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Invoke-ConnectivityTest' {
            (Get-Command Invoke-ConnectivityTest -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Show-ConnectivityReport' {
            (Get-Command Show-ConnectivityReport -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Export-ConnectivityReport' {
            (Get-Command Export-ConnectivityReport -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Invoke-TargetConnectivityTest' {
            (Get-Command Invoke-TargetConnectivityTest -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Invoke-TargetConnectivityWizard' {
            (Get-Command Invoke-TargetConnectivityWizard -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Test-TcpPortConnectivity' {
            (Get-Command Test-TcpPortConnectivity -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Test-UdpPortConnectivity' {
            (Get-Command Test-UdpPortConnectivity -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Test-LocalTcpListener' {
            (Get-Command Test-LocalTcpListener -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Test-LocalUdpListener' {
            (Get-Command Test-LocalUdpListener -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar New-ConnectivityTestPlan' {
            (Get-Command New-ConnectivityTestPlan -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Export-ConnectivityReportPdf' {
            (Get-Command Export-ConnectivityReportPdf -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Test-GatewayConnectivity' {
            (Get-Command Test-GatewayConnectivity -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Test-DnsResolution' {
            (Get-Command Test-DnsResolution -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Test-IcmpConnectivity' {
            (Get-Command Test-IcmpConnectivity -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Invoke-ConnectivityWizard' {
            (Get-Command Invoke-ConnectivityWizard -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
    }

    Context 'Contrato dos testes' {
        It 'Get-NetworkContext deve retornar objeto' {
            $context = Get-NetworkContext
            $context | Should -BeOfType [psobject]
        }

        It 'Test-TcpPortConnectivity deve retornar objeto de resultado' {
            $result = Test-TcpPortConnectivity -TargetAddress '127.0.0.1' -Port 1 -TimeoutSeconds 1
            $result | Should -BeOfType [psobject]
            $result.PSObject.Properties.Name | Should -Contain 'Classification'
        }

        It 'Test-UdpPortConnectivity deve retornar objeto de resultado' {
            $result = Test-UdpPortConnectivity -TargetAddress '127.0.0.1' -Port 1 -TimeoutSeconds 1
            $result | Should -BeOfType [psobject]
            $result.PSObject.Properties.Name | Should -Contain 'Classification'
        }

        It 'Invoke-TargetConnectivityTest deve testar TCP com lista de portas' {
            $report = Invoke-TargetConnectivityTest -TargetAddress '127.0.0.1' -Protocol TCP -PortSpec '1,2' -TimeoutSeconds 1
            $report.ReportType | Should -Be 'TargetConnectivity'
            @($report.Results).Count | Should -Be 2
            $report.Ports | Should -Be @(1, 2)
        }

        It 'Invoke-TargetConnectivityTest deve rejeitar porta invalida' {
            { Invoke-TargetConnectivityTest -TargetAddress '127.0.0.1' -Protocol TCP -PortSpec '0,70000' } |
                Should -Throw
        }
    }

    Context 'Listeners locais' {
        It 'Test-LocalTcpListener deve retornar objeto de resultado' {
            $result = Test-LocalTcpListener -Port 1
            $result | Should -BeOfType [psobject]
            $result.PSObject.Properties.Name | Should -Contain 'Classification'
            $result.PSObject.Properties.Name | Should -Contain 'Protocol'
            $result.Protocol | Should -Be 'TCP'
        }

        It 'Test-LocalUdpListener deve retornar objeto de resultado' {
            $result = Test-LocalUdpListener -Port 1
            $result | Should -BeOfType [psobject]
            $result.PSObject.Properties.Name | Should -Contain 'Classification'
            $result.Protocol | Should -Be 'UDP'
        }
    }

    Context 'Plano de teste' {
        It 'New-ConnectivityTestPlan deve retornar objeto com todos os campos' {
            $plan = New-ConnectivityTestPlan
            $plan | Should -BeOfType [psobject]
            $plan.PSObject.Properties.Name | Should -Contain 'IpTargets'
            $plan.PSObject.Properties.Name | Should -Contain 'DnsTargets'
            $plan.PSObject.Properties.Name | Should -Contain 'DomainTargets'
            $plan.PSObject.Properties.Name | Should -Contain 'TcpPort'
            $plan.PSObject.Properties.Name | Should -Contain 'Detailed'
        }

        It 'New-ConnectivityTestPlan deve aceitar parametros customizados' {
            $plan = New-ConnectivityTestPlan -IpTargets @('10.0.0.1') -TcpPort 80
            @($plan.IpTargets) | Should -Contain '10.0.0.1'
            $plan.TcpPort | Should -Be 80
        }

        It 'New-ConnectivityTestPlan deve rejeitar porta TCP invalida' {
            { New-ConnectivityTestPlan -TcpPort 0 } | Should -Throw
            { New-ConnectivityTestPlan -TcpPort 70000 } | Should -Throw
        }

        It 'DnsTargets e DomainTargets devem ter defaults distintos' {
            $plan = New-ConnectivityTestPlan
            $dns = ($plan.DnsTargets | Sort-Object) -join ','
            $domain = ($plan.DomainTargets | Sort-Object) -join ','
            $dns | Should -Not -Be $domain
        }
    }

    Context 'Exportacao PDF sem navegador' {
        It 'Export-ConnectivityReportPdf deve retornar falha graciosamente quando nao ha navegador' {
            $fakePath = Join-Path ([System.IO.Path]::GetTempPath()) 'wba-fake-report.html'
            $result = Export-ConnectivityReportPdf -HtmlPath $fakePath
            $result | Should -BeOfType [psobject]
            $result.Type | Should -Be 'PDF'
        }
    }

    Context 'Invoke-ConnectivityTest' {
        It 'Deve retornar objeto de relatorio com as propriedades esperadas' {
            $report = Invoke-ConnectivityTest -IpTargets @('127.0.0.1') -DnsTargets @('localhost') `
                -DomainTargets @('localhost') -TcpPort 80
            $report | Should -BeOfType [psobject]
            $report.PSObject.Properties.Name | Should -Contain 'ReportId'
            $report.PSObject.Properties.Name | Should -Contain 'Results'
            $report.PSObject.Properties.Name | Should -Contain 'Summary'
            $report.PSObject.Properties.Name | Should -Contain 'Context'
            $report.PSObject.Properties.Name | Should -Contain 'FinishedAt'
        }

        It 'Summary deve conter contadores de resultado' {
            $report = Invoke-ConnectivityTest -IpTargets @('127.0.0.1') -DnsTargets @('localhost') `
                -DomainTargets @('localhost') -TcpPort 80
            $summary = $report.Summary
            $summary.PSObject.Properties.Name | Should -Contain 'Total'
            $summary.PSObject.Properties.Name | Should -Contain 'Success'
            $summary.PSObject.Properties.Name | Should -Contain 'Failed'
        }
    }

    Context 'Exportacao HTML' {
        It 'Deve gerar um arquivo HTML com o relatório' {
            $report = [pscustomobject]@{
                ReportId   = 'TEST-REPORT'
                FinishedAt = Get-Date
                Context    = [pscustomobject]@{
                    Hostname        = 'HOST'
                    Username        = 'USER'
                    InterfaceAlias  = 'Ethernet'
                    IPv4Address     = '192.168.1.10'
                    PrefixLength    = 24
                    Gateway         = '192.168.1.1'
                    DnsServers      = @('1.1.1.1', '8.8.8.8')
                }
                Summary    = [pscustomobject]@{
                    Total = 1
                    Success = 1
                    Failed = 0
                    Warning = 0
                    Inconclusive = 0
                }
                Results    = @(
                    [pscustomobject]@{
                        TestName       = 'Teste ICMP'
                        Protocol       = 'ICMP'
                        Classification = 'Success'
                        Target         = '8.8.8.8'
                        Port           = $null
                        LatencyMs      = 12.3
                        ErrorMessage   = $null
                        Recommendation = 'OK'
                    }
                )
                Blocked    = $false
                BlockReason = $null
            }

            $temp = Join-Path ([System.IO.Path]::GetTempPath()) 'wba-connectivity-test.html'
            if (Test-Path $temp) { Remove-Item $temp -Force }

            $export = Export-ConnectivityReport -Report $report -Path $temp
            Test-Path $export.Path | Should -BeTrue

            $content = Get-Content -LiteralPath $export.Path -Raw
            $content | Should -Match 'Relat[óo]rio de Conectividade'
            $content | Should -Match 'charset=utf-8'

            $bytes = [System.IO.File]::ReadAllBytes($export.Path)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }
    }

    Context 'BCK-010 - Test-UdpPortConnectivity (deteccao via ICMP/timeout)' {
        It 'Classifica porta UDP fechada/sem-resposta sem lancar e dentro do timeout' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $r  = Test-UdpPortConnectivity -TargetAddress '127.0.0.1' -Port 9 -TimeoutSeconds 2
            $sw.Stop()
            $r.Protocol       | Should -Be 'UDP'
            $r.Classification | Should -BeIn @('Failed', 'Inconclusive', 'Success')
            $r.Status         | Should -BeIn @('Fechada', 'Sem resposta', 'Aberta', 'Falha')
            # -TimeoutSeconds agora e respeitado: nao deve exceder ~timeout + folga.
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 5
        }
    }

    Context 'BCK-010 - Export-ConnectivityReportPdf (valida PDF gerado)' {
        It 'Retorna Success=$false quando o navegador executa mas nao gera o PDF' {
            $script:stubBrowser = Join-Path $env:TEMP "wba_stub_browser_$([guid]::NewGuid().ToString('N')).cmd"
            Set-Content -LiteralPath $script:stubBrowser -Value '@exit /b 0' -Encoding ASCII
            Mock -CommandName 'Get-Command' -ModuleName 'WbaToolkit.Networking' -MockWith {
                [pscustomobject]@{ Path = $script:stubBrowser; Source = $script:stubBrowser }
            }
            $html = Join-Path $env:TEMP "wba_in_$([guid]::NewGuid().ToString('N')).html"
            Set-Content -LiteralPath $html -Value '<html></html>' -Encoding UTF8
            $pdf = [System.IO.Path]::ChangeExtension($html, '.pdf')
            try {
                $r = Export-ConnectivityReportPdf -HtmlPath $html -PdfPath $pdf
                $r.Success | Should -BeFalse
                $r.Message | Should -Match 'nao foi gerado'
            }
            finally {
                Remove-Item -LiteralPath $script:stubBrowser, $html, $pdf -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
