function Invoke-TargetConnectivityWizard {
    <#
    .SYNOPSIS
        Executa wizard para teste de conectividade contra alvo informado pelo operador.
    #>
    [CmdletBinding()]
    param()

    # WBA-DOCS: Category=Networking; Related=Invoke-TargetConnectivityTest,Show-ConnectivityReport; Manual=Wizard interativo para teste direcionado

    function Resolve-WizardProtocolSelection {
        [CmdletBinding()]
        param([Parameter(Mandatory = $true)][string]$Selection)

        $protocols = New-Object 'System.Collections.Generic.List[string]'
        $tokens = $Selection -split '[,\s;]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($token in $tokens) {
            switch -Regex ($token.Trim().ToLowerInvariant()) {
                '^(1|tcp)$' { if (-not $protocols.Contains('TCP')) { $protocols.Add('TCP') }; continue }
                '^(2|udp)$' { if (-not $protocols.Contains('UDP')) { $protocols.Add('UDP') }; continue }
                '^(3|icmp|ping)$' { if (-not $protocols.Contains('ICMP')) { $protocols.Add('ICMP') }; continue }
                '^(4|all|todos|tudo)$' {
                    foreach ($protocol in @('TCP', 'UDP', 'ICMP')) {
                        if (-not $protocols.Contains($protocol)) { $protocols.Add($protocol) }
                    }
                    continue
                }
                default {
                    throw "Opcao de protocolo invalida: $token"
                }
            }
        }

        return @($protocols)
    }

    Write-Host ''
    Write-Host 'WBA Target Connectivity Tester' -ForegroundColor Cyan

    do {
        $target = Read-Host 'Informe o IP ou nome do destino'
    } while ([string]::IsNullOrWhiteSpace($target))

    Write-Host ''
    Write-Host 'Protocolo: informe uma opcao, lista separada por virgula ou espaco.' -ForegroundColor Cyan
    Write-Host 'Exemplos: 1 | tcp | 1,3 | tcp udp | todos'
    Write-Host '1. TCP'
    Write-Host '2. UDP'
    Write-Host '3. ICMP'
    Write-Host '4. Todos'

    $protocols = @()
    while (@($protocols).Count -eq 0) {
        try {
            $protocols = @(Resolve-WizardProtocolSelection -Selection (Read-Host 'Escolha protocolo(s)'))
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }

    $portSpec = $null
    if (@($protocols | Where-Object { $_ -in @('TCP', 'UDP') }).Count -gt 0) {
        do {
            $portSpec = Read-Host 'Informe porta, lista ou range (ex: 443, 80,443,3389, 8000-8010)'
        } while ([string]::IsNullOrWhiteSpace($portSpec))
    }

    $reports = foreach ($protocol in $protocols) {
        Invoke-TargetConnectivityTest -TargetAddress $target -Protocol $protocol -PortSpec $portSpec
    }

    $resultItems = @($reports | ForEach-Object { $_.Results })
    $ports = @($reports | ForEach-Object { $_.Ports } | Sort-Object -Unique)
    $report = [pscustomobject]@{
        ReportId    = [guid]::NewGuid().ToString()
        ReportType  = 'TargetConnectivity'
        StartedAt   = @($reports | Sort-Object StartedAt | Select-Object -First 1 -ExpandProperty StartedAt)
        FinishedAt  = Get-Date
        Target      = $target
        Protocol    = if (@($protocols).Count -eq 3) { 'All' } else { @($protocols) -join ',' }
        PortSpec    = $portSpec
        Ports       = $ports
        Context     = @($reports | Select-Object -First 1 -ExpandProperty Context)
        Results     = $resultItems
        Summary     = Get-ConnectivitySummary -Results $resultItems
        Blocked     = $false
        BlockReason = $null
    }

    Show-ConnectivityReport -Report $report
    $report
}
