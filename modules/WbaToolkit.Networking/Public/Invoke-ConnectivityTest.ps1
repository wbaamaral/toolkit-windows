function Invoke-ConnectivityTest {
    <#
    .SYNOPSIS
        Executa a bateria de conectividade e retorna um relatório estruturado.
    #>
    [CmdletBinding()]
    param(
        [Alias('Detalhado')]
        [switch]$Detailed,

        [Parameter(Mandatory = $false)]
        [string[]]$IpTargets = @('8.8.8.8', '8.8.4.4', '1.1.1.1', '9.9.9.9'),

        [Parameter(Mandatory = $false)]
        [string[]]$DnsTargets = @('www.google.com', 'www.microsoft.com', 'www.cloudflare.com', 'www.msftconnecttest.com'),

        [Parameter(Mandatory = $false)]
        [string[]]$DomainTargets = @('www.google.com', 'www.microsoft.com', 'www.cloudflare.com', 'www.amazon.com'),

        [Parameter(Mandatory = $false)]
        [int]$TcpPort = 443
    )

    $startedAt = Get-Date
    $context   = Get-NetworkContext
    $results   = [System.Collections.ArrayList]::new()
    $blocked   = $false
    $reason    = $null

    if (-not $context.InterfaceAlias) {
        $null = $results.Add((New-ConnectivityResult -TestName 'Contexto de rede' -Category 'Contexto' -Success $false -Status 'Sem adaptador ativo' -Classification 'Error' `
            -Recommendation 'Nenhum adaptador ativo foi encontrado.' -StartedAt $startedAt -FinishedAt (Get-Date) -Details $context))
        $blocked = $true
        $reason = 'Nenhum adaptador ativo encontrado.'
    }
    elseif (-not $context.Gateway) {
        $null = $results.Add((New-ConnectivityResult -TestName 'Contexto de rede' -Category 'Contexto' -Success $false -Status 'Gateway ausente' -Classification 'Error' `
            -Recommendation 'Configure uma rota padrão antes de continuar.' -StartedAt $startedAt -FinishedAt (Get-Date) -Details $context))
        $blocked = $true
        $reason = 'Gateway padrão não configurado.'
    }
    elseif (-not $context.DnsServers -or @($context.DnsServers).Count -eq 0) {
        $null = $results.Add((New-ConnectivityResult -TestName 'Contexto de rede' -Category 'Contexto' -Success $false -Status 'DNS ausente' -Classification 'Error' `
            -Recommendation 'Configure ao menos um servidor DNS antes de continuar.' -StartedAt $startedAt -FinishedAt (Get-Date) -Details $context))
        $blocked = $true
        $reason = 'Servidores DNS não configurados.'
    }
    else {
        $null = $results.Add((New-ConnectivityResult -TestName 'Contexto de rede' -Category 'Contexto' -Success $true -Status 'OK' -Classification 'Success' `
            -Recommendation 'Contexto de rede detectado com sucesso.' -StartedAt $startedAt -FinishedAt (Get-Date) -Details $context))
    }

    if (-not $blocked) {
        foreach ($target in $IpTargets) {
            $null = $results.Add((Test-IcmpConnectivity -TargetAddress $target))
        }

        foreach ($target in @('nic.br', 'registro.br')) {
            $null = $results.Add((Test-TcpPortConnectivity -TargetAddress $target -Port $TcpPort -Scope 'WAN' -Direction 'Outbound'))
        }

        foreach ($name in $DnsTargets) {
            $null = $results.Add((Test-DnsResolution -Name $name))
        }

        foreach ($name in $DomainTargets) {
            $icmp = Test-IcmpConnectivity -TargetAddress $name
            $null = $results.Add($icmp)

            if (-not $icmp.Success) {
                $null = $results.Add((Test-TcpPortConnectivity -TargetAddress $name -Port $TcpPort -Scope 'WAN' -Direction 'Outbound'))
            }
        }

        # Teste de velocidade de download
        if ($Detailed) {
            Write-Host ''
            Write-Host "  Testando velocidade de download..." -NoNewline -ForegroundColor Cyan
            $speedResult = Test-DownloadSpeed
            if ($speedResult.Status -eq 'OK') {
                Write-Host " OK" -ForegroundColor Green
            }
            else {
                Write-Host " Erro" -ForegroundColor Red
            }
            $null = $results.Add((New-ConnectivityResult -TestName 'Velocidade de download' -Category 'Velocidade' `
                -Success ($speedResult.Status -eq 'OK') -Status $speedResult.Status `
                -Classification $(if ($speedResult.Status -eq 'OK') { 'Success' } else { 'Failed' }) `
                -Recommendation $speedResult.Message `
                -StartedAt $startedAt -FinishedAt (Get-Date) `
                -Details $speedResult))
        }
    }

    $finishedAt = Get-Date
    $resultItems = @($results)
    $summary = Get-ConnectivitySummary -Results $resultItems

    $report = [pscustomobject]@{
        ReportId      = [guid]::NewGuid().ToString()
        StartedAt     = $startedAt
        FinishedAt    = $finishedAt
        Detailed      = [bool]$Detailed
        Context       = $context
        Results       = $resultItems
        Summary       = $summary
        Blocked       = $blocked
        BlockReason   = $reason
    }

    $report
}
