#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostica a saude do cliente Windows em relacao ao Active Directory.

.DESCRIPTION
    Consolida a leitura do estado do cliente em relacao ao AD: ingresso no dominio,
    canal seguro, DNS, resolucao de registros SRV, acesso a SYSVOL/NETLOGON,
    sincronizacao de hora, conectividade com o DC, servicos essenciais e situacao
    da conta do computador no AD quando o modulo RSAT estiver disponivel.

    No modo Diagnostico, o script e somente leitura. No modo Assistido, quando o
    canal seguro ou a hora do cliente estiverem comprometidos, o operador pode
    confirmar o reparo guiado.

.PARAMETER Modo
    Diagnostico ou Assistido. Assistido permite reparo guiado do canal seguro.

.PARAMETER Hora
    Habilita o reparo guiado da sincronização de hora em modo Assistido.

.PARAMETER Canal
    Habilita o reparo guiado do canal seguro em modo Assistido.

.PARAMETER DomainFQDN
    FQDN do dominio. Quando omitido, o script tenta inferir do ambiente.

.PARAMETER DomainNetBIOS
    Nome NetBIOS do dominio. Quando omitido, o script deriva do FQDN.

.PARAMETER PreferredDc
    Controlador de dominio preferencial.

.PARAMETER DnsServers
    Servidores DNS esperados no cliente. Quando informados, o script aponta
    divergencias de configuracao local.

.PARAMETER Path
    Raiz de relatorios. Quando omitido, usa a raiz persistente do toolkit.

.PARAMETER Help
    Exibe a ajuda resumida do script e encerra.

.EXAMPLE
    .\diagnosticar-ad-cliente.ps1

.EXAMPLE
    .\diagnosticar-ad-cliente.ps1 -Modo Assistido -Hora -Canal -DomainFQDN wba.test
#>
[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Assistido')]
    [string]$Modo = 'Diagnostico',

    [switch]$Hora,

    [switch]$Canal,

    [string]$DomainFQDN = '',

    [string]$DomainNetBIOS = '',

    [string]$PreferredDc = '',

    [string[]]$DnsServers,

    [switch]$GerarHtml,

    [switch]$AbrirRelatorio,

    [Alias('DiretorioSaida')]
    [string]$Path,

    [switch]$Help
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
try { chcp 65001 | Out-Null } catch { }

$ScriptName = if ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } else { Split-Path -Leaf $PSCommandPath }
$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

$ToolkitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Force -ErrorAction Stop
Import-Module (Join-Path $ToolkitRoot 'modules/WbaToolkit.Startup/WbaToolkit.Startup.psd1') -Force -ErrorAction Stop

$ScriptVersion = 'v1.0'
$script:Checks = New-Object 'System.Collections.Generic.List[object]'
$script:ReportSession = $null
$script:TextReportPath = $null
$script:HtmlReportPath = $null
$script:ComputerName = $env:COMPUTERNAME
$script:Domain = $DomainFQDN
$script:NetBIOS = $DomainNetBIOS
$script:TargetDc = $PreferredDc

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Diagnóstico de Cliente de Domínio (AD) — $ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -Modo '<modo>'         Diagnostico (padrao) ou Assistido (permite reparo guiado)."
    Write-Host "  -Hora                  Habilita o reparo guiado da hora (modo Assistido)."
    Write-Host "  -Canal                 Habilita o reparo guiado do canal seguro (modo Assistido)."
    Write-Host "  -DomainFQDN '<fqdn>'   FQDN do dominio. Padrao: inferido do ambiente."
    Write-Host "  -DomainNetBIOS '<nb>'  Nome NetBIOS do dominio. Padrao: derivado do FQDN."
    Write-Host "  -PreferredDc '<dc>'    Controlador de dominio preferencial."
    Write-Host "  -DnsServers <lista>    Servidores DNS esperados no cliente."
    Write-Host "  -GerarHtml             Gera tambem o relatorio em HTML."
    Write-Host "  -AbrirRelatorio        Abre o relatorio HTML ao final."
    Write-Host "  -DiretorioSaida '<dir>' Raiz de relatorios. Padrao: raiz persistente do toolkit."
    Write-Host "  -Help                  Esta ajuda."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Modo Assistido -Hora -Canal -DomainFQDN wba.test"
    Write-Host ""
}

function Add-AdCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'AVISO', 'FALHA', 'PULADO')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [Parameter(Mandatory = $false)][string]$Recommendation = '',
        [Parameter(Mandatory = $false)][int]$Penalty = 0,
        [switch]$Critical
    )

    $script:Checks.Add([pscustomobject]@{
        Categoria     = $Category
        Nome          = $Name
        Status        = $Status
        Detalhe       = $Detail
        Recomendacao  = $Recommendation
        Penalidade    = $Penalty
        Critico       = [bool]$Critical
    }) | Out-Null
}

function Resolve-AdContext {
    [CmdletBinding()]
    param()

    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $script:ComputerName = $computer.Name

    if ([string]::IsNullOrWhiteSpace($script:Domain)) {
        if ($computer.PartOfDomain -and -not [string]::IsNullOrWhiteSpace($computer.Domain)) {
            $script:Domain = $computer.Domain
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:USERDNSDOMAIN)) {
            $script:Domain = $env:USERDNSDOMAIN
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:NetBIOS) -and -not [string]::IsNullOrWhiteSpace($script:Domain)) {
        $script:NetBIOS = ($script:Domain -split '\.')[0].ToUpperInvariant()
    }

    if ([string]::IsNullOrWhiteSpace($script:TargetDc) -and -not [string]::IsNullOrWhiteSpace($script:Domain)) {
        $nltest = Invoke-ExternalCommand -FilePath 'nltest' -ArgumentList @("/dsgetdc:$script:Domain")
        if ($nltest.Output -match 'DC:\s*\\\\(\S+)') {
            $script:TargetDc = $Matches[1]
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:TargetDc) -and -not [string]::IsNullOrWhiteSpace($script:Domain)) {
        $script:TargetDc = $script:Domain
    }

    return [pscustomobject]@{
        ComputerName = $script:ComputerName
        PartOfDomain = [bool]$computer.PartOfDomain
        Domain = $script:Domain
        DomainNetBIOS = $script:NetBIOS
        PreferredDc = $script:TargetDc
    }
}

function Test-AdPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($HostName, $Port)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($client) { $client.Close() }
    }
}

function Test-AdDnsConfiguration {
    [CmdletBinding()]
    param()

    $expected = @($DnsServers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $adapters = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses })
    $configured = @($adapters | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })

    if ($expected.Count -eq 0) {
        Add-AdCheck -Category 'DNS' -Name 'Configuração DNS' -Status 'AVISO' -Detail 'Nenhum DNS esperado foi informado. Foi analisada apenas a configuração local.' -Recommendation 'Se quiser validar um baseline, informe -DnsServers.' -Penalty 5
    }
    else {
        $missing = @($expected | Where-Object { $_ -notin $configured })
        if ($missing.Count -eq 0) {
            Add-AdCheck -Category 'DNS' -Name 'Configuração DNS' -Status 'OK' -Detail "DNS esperado presente: $($expected -join ', ')" -Penalty 0
        }
        else {
            Add-AdCheck -Category 'DNS' -Name 'Configuração DNS' -Status 'AVISO' -Detail "DNS esperado ausente: $($missing -join ', ')" -Recommendation 'Corrija os DNS do cliente para apontar ao AD.' -Penalty 10
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:Domain)) {
        $queries = @(
            [pscustomobject]@{ Name = $script:Domain; Type = 'A'; Label = 'Host do dominio' },
            [pscustomobject]@{ Name = "_ldap._tcp.$script:Domain"; Type = 'SRV'; Label = 'SRV LDAP' },
            [pscustomobject]@{ Name = "_kerberos._tcp.$script:Domain"; Type = 'SRV'; Label = 'SRV Kerberos TCP' },
            [pscustomobject]@{ Name = "_kerberos._udp.$script:Domain"; Type = 'SRV'; Label = 'SRV Kerberos UDP' }
        )

        foreach ($query in $queries) {
            try {
                $records = Resolve-DnsName -Name $query.Name -Type $query.Type -ErrorAction Stop
                Add-AdCheck -Category 'DNS' -Name $query.Label -Status 'OK' -Detail "Resolução OK: $($query.Name)" -Penalty 0
            }
            catch {
                Add-AdCheck -Category 'DNS' -Name $query.Label -Status 'FALHA' -Detail "Falha ao resolver $($query.Name): $($_.Exception.Message)" -Recommendation 'Valide DNS no cliente e nos controladores de domínio.' -Penalty 20 -Critical
            }
        }
    }
}

function Test-AdConnectivity {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:TargetDc)) {
        Add-AdCheck -Category 'Conectividade' -Name 'Controlador de domínio' -Status 'PULADO' -Detail 'Nenhum DC pôde ser identificado.' -Penalty 10
        return
    }

    $ping = Test-Connection -ComputerName $script:TargetDc -Count 2 -ErrorAction SilentlyContinue
    if ($ping) {
        $rttProperty = if ((@($ping)[0].PSObject.Properties.Name) -contains 'Latency') { 'Latency' } else { 'ResponseTime' }
        $rtt = [math]::Round((($ping | Measure-Object -Property $rttProperty -Average).Average), 1)
        Add-AdCheck -Category 'Conectividade' -Name 'Ping ao DC' -Status 'OK' -Detail "RTT médio para $script:TargetDc: $rtt ms" -Penalty 0
    }
    else {
        Add-AdCheck -Category 'Conectividade' -Name 'Ping ao DC' -Status 'FALHA' -Detail "Sem resposta ICMP de $script:TargetDc" -Recommendation 'Verifique rota, firewall e conectividade física.' -Penalty 15 -Critical
    }

    if (Test-AdPort -HostName $script:TargetDc -Port 389) {
        Add-AdCheck -Category 'Conectividade' -Name 'LDAP 389' -Status 'OK' -Detail "Porta 389 acessível em $script:TargetDc" -Penalty 0
    }
    else {
        Add-AdCheck -Category 'Conectividade' -Name 'LDAP 389' -Status 'FALHA' -Detail "Porta 389 indisponível em $script:TargetDc" -Recommendation 'O cliente precisa alcançar LDAP para consultar o AD.' -Penalty 20 -Critical
    }

    if (Test-AdPort -HostName $script:TargetDc -Port 445) {
        Add-AdCheck -Category 'Conectividade' -Name 'SMB 445' -Status 'OK' -Detail "Porta 445 acessível em $script:TargetDc (SYSVOL/NETLOGON)" -Penalty 0
    }
    else {
        Add-AdCheck -Category 'Conectividade' -Name 'SMB 445' -Status 'FALHA' -Detail "Porta 445 indisponível em $script:TargetDc" -Recommendation 'Sem SMB o cliente não acessa SYSVOL e NETLOGON.' -Penalty 20 -Critical
    }
}

function Test-AdShares {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:Domain)) {
        Add-AdCheck -Category 'Shares' -Name 'SYSVOL/NETLOGON' -Status 'PULADO' -Detail 'Domínio não identificado.' -Penalty 10
        return
    }

    $shareHost = if (-not [string]::IsNullOrWhiteSpace($script:TargetDc)) { $script:TargetDc } else { $script:Domain }
    foreach ($share in @('SYSVOL', 'NETLOGON')) {
        $path = "\\$shareHost\$share"
        if (Test-Path -LiteralPath $path) {
            Add-AdCheck -Category 'Shares' -Name $share -Status 'OK' -Detail "Acesso OK: $path" -Penalty 0
        }
        else {
            Add-AdCheck -Category 'Shares' -Name $share -Status 'FALHA' -Detail "Sem acesso: $path" -Recommendation "Verifique o compartilhamento $share no DC." -Penalty 20 -Critical
        }
    }
}

function Test-AdSecureChannel {
    [CmdletBinding()]
    param()

    if (-not $script:ReportSession) { }

    try {
        $secure = Test-ComputerSecureChannel -ErrorAction Stop
        if ($secure) {
            Add-AdCheck -Category 'Domínio' -Name 'Canal seguro' -Status 'OK' -Detail 'Secure channel íntegro.' -Penalty 0
        }
        else {
            Add-AdCheck -Category 'Domínio' -Name 'Canal seguro' -Status 'FALHA' -Detail 'Secure channel quebrado.' -Recommendation 'Em modo assistido, use o reparo guiado.' -Penalty 30 -Critical
            if ($Modo -eq 'Assistido' -and $Canal -and (Read-YesNo -Question 'Deseja reparar o canal seguro agora?' -DefaultYes $true)) {
                $cred = Get-Credential -Message 'Credencial de domínio para reparar o canal seguro'
                try {
                    if ([string]::IsNullOrWhiteSpace($script:TargetDc)) {
                        Reset-ComputerMachinePassword -Credential $cred -ErrorAction Stop
                    }
                    else {
                        Reset-ComputerMachinePassword -Server $script:TargetDc -Credential $cred -ErrorAction Stop
                    }
                    $post = Test-ComputerSecureChannel -ErrorAction Stop
                    if ($post) {
                        Add-AdCheck -Category 'Domínio' -Name 'Reparo do canal seguro' -Status 'OK' -Detail 'Reparo concluído com sucesso.' -Penalty 0
                    }
                    else {
                        Add-AdCheck -Category 'Domínio' -Name 'Reparo do canal seguro' -Status 'FALHA' -Detail 'O reparo foi executado, mas o canal ainda falha.' -Penalty 15 -Critical
                    }
                }
                catch {
                    Add-AdCheck -Category 'Domínio' -Name 'Reparo do canal seguro' -Status 'FALHA' -Detail $_.Exception.Message -Recommendation 'Verifique credenciais e conectividade com o DC.' -Penalty 15 -Critical
                }
            }
        }
    }
    catch {
        Add-AdCheck -Category 'Domínio' -Name 'Canal seguro' -Status 'FALHA' -Detail $_.Exception.Message -Recommendation 'Falha ao consultar o secure channel.' -Penalty 20 -Critical
    }
}

function Test-AdTimeSync {
    [CmdletBinding()]
    param()

    $source = ''
    $status = 'AVISO'
    $detail = ''
    try {
        $sourceInfo = Invoke-ExternalCommand -FilePath 'w32tm' -ArgumentList @('/query', '/source')
        $source = ($sourceInfo.Output | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($source)) {
            $source = 'desconhecido'
        }

        if ($source -match 'Domain Hierarchy|^.*\bDC\b.*$') {
            $status = 'OK'
            $detail = "Fonte de tempo: $source"
            Add-AdCheck -Category 'Tempo' -Name 'Sincronização de hora' -Status $status -Detail $detail -Penalty 0
        }
        else {
            $detail = "Fonte de tempo não-dominío: $source"
            Add-AdCheck -Category 'Tempo' -Name 'Sincronização de hora' -Status $status -Detail $detail -Recommendation 'Kerberos depende de horário alinhado ao domínio.' -Penalty 5
        }
    }
    catch {
        Add-AdCheck -Category 'Tempo' -Name 'Sincronização de hora' -Status 'AVISO' -Detail $_.Exception.Message -Penalty 5
    }
}

function Set-AdCheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'AVISO', 'FALHA', 'PULADO')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [Parameter(Mandatory = $false)][string]$Recommendation = '',
        [Parameter(Mandatory = $false)][int]$Penalty = 0,
        [switch]$Critical
    )

    foreach ($check in $script:Checks) {
        if ($check.Categoria -eq $Category -and $check.Nome -eq $Name) {
            $check.Status = $Status
            $check.Detalhe = $Detail
            $check.Recomendacao = $Recommendation
            $check.Penalidade = $Penalty
            $check.Critico = [bool]$Critical
            return $true
        }
    }

    return $false
}

function Repair-AdTimeSync {
    [CmdletBinding()]
    param()

    Write-Section 'Tempo - reparo guiado'

    if ($Modo -ne 'Assistido') {
        Add-AdCheck -Category 'Tempo' -Name 'Reparo da hora' -Status 'PULADO' -Detail 'Correção de hora disponível apenas em modo Assistido.' -Recommendation 'Reexecute com -Modo Assistido -Hora.' -Penalty 0
        return
    }

    if (-not (Read-YesNo -Question 'Deseja corrigir a sincronizacao de hora agora?' -DefaultYes $true)) {
        Add-AdCheck -Category 'Tempo' -Name 'Reparo da hora' -Status 'PULADO' -Detail 'Correção de hora cancelada pelo operador.' -Penalty 0
        return
    }

    try {
        $steps = @(
            @{ FilePath = 'w32tm'; ArgumentList = @('/config', '/syncfromflags:domhier', '/update'); Label = 'Aplicando politica de sincronizacao' },
            @{ FilePath = 'net';    ArgumentList = @('stop', 'w32time'); Label = 'Parando W32Time' },
            @{ FilePath = 'net';    ArgumentList = @('start', 'w32time'); Label = 'Iniciando W32Time' },
            @{ FilePath = 'w32tm';  ArgumentList = @('/resync', '/force'); Label = 'Reforcando sincronizacao' }
        )

        foreach ($step in $steps) {
            Write-Info $step.Label
            $result = Invoke-ExternalCommand -FilePath $step.FilePath -ArgumentList $step.ArgumentList
            if ($result.ExitCode -ne 0) {
                throw "$($step.Label): $($result.Output)"
            }
        }

        Start-Sleep -Seconds 2
        $post = Invoke-ExternalCommand -FilePath 'w32tm' -ArgumentList @('/query', '/source')
        $source = ($post.Output | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($source)) {
            $source = 'desconhecido'
        }

        if ($source -match 'Domain Hierarchy|^.*\bDC\b.*$') {
            Set-AdCheckResult -Category 'Tempo' -Name 'Sincronização de hora' -Status 'OK' -Detail "Sincronização corrigida. Fonte de tempo: $source" -Penalty 0
            Add-AdCheck -Category 'Tempo' -Name 'Reparo da hora' -Status 'OK' -Detail "Reparo concluído com sucesso. Fonte atual: $source" -Penalty 0
        }
        else {
            Set-AdCheckResult -Category 'Tempo' -Name 'Sincronização de hora' -Status 'AVISO' -Detail "Sincronização executada, mas a fonte ainda não é do domínio: $source" -Recommendation 'Valide a fonte de tempo do cliente e do controlador de domínio.' -Penalty 5
            Add-AdCheck -Category 'Tempo' -Name 'Reparo da hora' -Status 'AVISO' -Detail "Reparo executado, mas a fonte permanece fora do domínio: $source" -Penalty 5
        }
    }
    catch {
        Add-AdCheck -Category 'Tempo' -Name 'Reparo da hora' -Status 'FALHA' -Detail $_.Exception.Message -Recommendation 'Verifique conectividade com o DC e permissões de administrador.' -Penalty 10 -Critical
    }
}

function Test-AdServices {
    [CmdletBinding()]
    param()

    $serviceNames = @('gpsvc', 'Netlogon', 'Dnscache', 'W32Time', 'LanmanWorkstation')
    $states = @(Get-ServiceStartupState -ServiceName $serviceNames)
    foreach ($svc in $states) {
        if ($svc.Status -eq 'Running') {
            Add-AdCheck -Category 'Serviços' -Name $svc.Name -Status 'OK' -Detail "Status=$($svc.Status); StartType=$($svc.StartType)" -Penalty 0
        }
        else {
            Add-AdCheck -Category 'Serviços' -Name $svc.Name -Status 'AVISO' -Detail "Status=$($svc.Status); StartType=$($svc.StartType)" -Recommendation 'O serviço precisa estar disponível para o cliente AD.' -Penalty 5
        }
    }
}

function Test-AdMachineObject {
    [CmdletBinding()]
    param()

    $module = Get-Module -ListAvailable ActiveDirectory | Select-Object -First 1
    if (-not $module -or [string]::IsNullOrWhiteSpace($script:Domain)) {
        Add-AdCheck -Category 'AD' -Name 'Conta de computador no AD' -Status 'AVISO' -Detail 'RSAT ActiveDirectory não disponível ou domínio não identificado.' -Penalty 5
        return
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $adComputer = Get-ADComputer -Identity $script:ComputerName -Server $script:Domain -Properties Enabled,LastLogonDate,PasswordLastSet -ErrorAction Stop
        $enabled = if ($adComputer.Enabled) { 'habilitada' } else { 'desabilitada' }
        Add-AdCheck -Category 'AD' -Name 'Conta de computador no AD' -Status 'OK' -Detail "Conta localizada: $($adComputer.DistinguishedName); estado: $enabled; PasswordLastSet=$($adComputer.PasswordLastSet)" -Penalty 0
    }
    catch {
        Add-AdCheck -Category 'AD' -Name 'Conta de computador no AD' -Status 'AVISO' -Detail $_.Exception.Message -Recommendation 'Verifique RSAT, credenciais e a presença do objeto no AD.' -Penalty 5
    }
}

function Get-AdHealthSummary {
    $score = 100
    foreach ($check in $script:Checks) {
        $score -= [math]::Max(0, [int]$check.Penalidade)
    }
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    $critical = @($script:Checks | Where-Object { $_.Status -eq 'FALHA' -and $_.Critico })
    $warn = @($script:Checks | Where-Object { $_.Status -eq 'AVISO' })

    $label = if ($critical.Count -gt 0) {
        'Crítico'
    }
    elseif ($warn.Count -gt 0) {
        if ($score -ge 75) { 'Bom' } else { 'Degradado' }
    }
    else {
        'Excelente'
    }

    [pscustomobject]@{
        Score = $score
        Label = $label
        CriticalCount = $critical.Count
        WarningCount = $warn.Count
    }
}

function ConvertTo-AdHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Summary,
        [Parameter(Mandatory = $true)][object[]]$Checks
    )

    $rows = foreach ($check in $Checks) {
        $color = switch ($check.Status) {
            'OK' { '#0f766e' }
            'AVISO' { '#b45309' }
            'FALHA' { '#b91c1c' }
            default { '#4b5563' }
        }

        "<tr><td>$(ConvertTo-HtmlSafe -Value $check.Categoria)</td><td>$(ConvertTo-HtmlSafe -Value $check.Nome)</td><td style='color:$color;font-weight:700'>$(ConvertTo-HtmlSafe -Value $check.Status)</td><td>$(ConvertTo-HtmlSafe -Value $check.Detalhe)</td><td>$(ConvertTo-HtmlSafe -Value $check.Recomendacao)</td></tr>"
    }

    @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Diagnóstico AD - $([System.Net.WebUtility]::HtmlEncode($script:ComputerName))</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #111827; }
h1, h2 { margin-bottom: 0.2rem; }
.summary { display: grid; grid-template-columns: repeat(4, minmax(0,1fr)); gap: 12px; margin: 16px 0 24px; }
.card { border: 1px solid #d1d5db; border-radius: 10px; padding: 12px 14px; background: #f9fafb; }
.label { color: #6b7280; font-size: 0.9rem; }
.value { font-size: 1.3rem; font-weight: 700; }
table { width: 100%; border-collapse: collapse; }
th, td { border: 1px solid #e5e7eb; padding: 8px; vertical-align: top; }
th { background: #f3f4f6; text-align: left; }
</style>
</head>
<body>
<h1>Diagnóstico do cliente AD</h1>
<p>Computador: <strong>$([System.Net.WebUtility]::HtmlEncode($script:ComputerName))</strong></p>
<p>Domínio: <strong>$([System.Net.WebUtility]::HtmlEncode($script:Domain))</strong> | DC: <strong>$([System.Net.WebUtility]::HtmlEncode($script:TargetDc))</strong> | Modo: <strong>$Modo</strong></p>
<div class="summary">
<div class="card"><div class="label">Status</div><div class="value">$([System.Net.WebUtility]::HtmlEncode($Summary.Label))</div></div>
<div class="card"><div class="label">Reputação</div><div class="value">$($Summary.Score)/100</div></div>
<div class="card"><div class="label">Falhas críticas</div><div class="value">$($Summary.CriticalCount)</div></div>
<div class="card"><div class="label">Avisos</div><div class="value">$($Summary.WarningCount)</div></div>
</div>
<table>
<thead><tr><th>Categoria</th><th>Checagem</th><th>Status</th><th>Detalhe</th><th>Recomendação</th></tr></thead>
<tbody>
$($rows -join "`r`n")
</tbody>
</table>
</body>
</html>
"@
}

function Write-AdReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Summary
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Diagnóstico do cliente AD - $ScriptVersion") | Out-Null
    $lines.Add("Computador : $script:ComputerName") | Out-Null
    $lines.Add("Domínio    : $script:Domain") | Out-Null
    $lines.Add("DC alvo    : $script:TargetDc") | Out-Null
    $lines.Add("Modo       : $Modo") | Out-Null
    $lines.Add("Status     : $($Summary.Label)") | Out-Null
    $lines.Add("Reputação  : $($Summary.Score)/100") | Out-Null
    $lines.Add("Falhas criticas : $($Summary.CriticalCount)") | Out-Null
    $lines.Add("Avisos     : $($Summary.WarningCount)") | Out-Null
    $lines.Add('') | Out-Null

    foreach ($check in $script:Checks) {
        $lines.Add(("[{0}] {1} - {2} :: {3}" -f $check.Categoria, $check.Nome, $check.Status, $check.Detalhe)) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($check.Recomendacao)) {
            $lines.Add("  Recomendação: $($check.Recomendacao)") | Out-Null
        }
    }

    Write-TextFileUtf8 -Path $script:TextReportPath -Content (($lines -join "`r`n") + "`r`n")

    if ($GerarHtml) {
        $html = ConvertTo-AdHtml -Summary $Summary -Checks $script:Checks.ToArray()
        Write-TextFileUtf8 -Path $script:HtmlReportPath -Content $html
    }
}

if ($Help) { Show-Help; exit 0 }

if (-not (Test-IsAdministrator)) {
    Write-Warn 'Privilegio de Administrador necessario. Solicitando elevacao...'
    $relaunchArgs = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { "-$($kv.Key)" }
        } else {
            "-$($kv.Key)"; "$($kv.Value)"
        }
    }
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $relaunchArgs
    Start-Process powershell.exe -ArgumentList $allArgs -Verb RunAs
    exit
}

$script:ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'ActiveDirectory'
$script:TextReportPath = Join-Path $script:ReportSession.Path 'diagnostico-ad-cliente.txt'
$script:HtmlReportPath = Join-Path $script:ReportSession.Path 'diagnostico-ad-cliente.html'

Write-Title "Diagnóstico do cliente AD - $ScriptVersion"
$context = Resolve-AdContext
Write-Info "Computador : $($context.ComputerName)"
Write-Info "Domínio    : $($context.Domain)"
Write-Info "NetBIOS    : $($context.DomainNetBIOS)"
Write-Info "DC alvo    : $($context.PreferredDc)"

Add-AdCheck -Category 'Domínio' -Name 'Ingresso no domínio' -Status $(if ($context.PartOfDomain) { 'OK' } else { 'FALHA' }) -Detail $(if ($context.PartOfDomain) { 'Cliente ingressado em domínio.' } else { 'Cliente não está ingressado em domínio.' }) -Recommendation $(if ($context.PartOfDomain) { '' } else { 'Ingressar a estação no domínio antes de aplicar políticas AD.' }) -Penalty $(if ($context.PartOfDomain) { 0 } else { 30 }) -Critical:(!$context.PartOfDomain)

Test-AdDnsConfiguration
Test-AdConnectivity
Test-AdShares
Test-AdSecureChannel
Test-AdTimeSync
if ($Hora) {
    Repair-AdTimeSync
}
Test-AdServices
Test-AdMachineObject

if ($context.PartOfDomain -and -not [string]::IsNullOrWhiteSpace($context.Domain)) {
    try {
        $gpresultPath = Join-Path $script:ReportSession.LogsPath 'gpresult-computer.txt'
        $gpresult = Invoke-ExternalCommand -FilePath 'gpresult' -ArgumentList @('/r', '/scope', 'computer')
        $gpresultContent = if ($null -ne $gpresult.Output) { [string]$gpresult.Output } else { '' }
        Write-TextFileUtf8 -Path $gpresultPath -Content ($gpresultContent + "`r`n")
        Add-AdCheck -Category 'GPO' -Name 'gpresult' -Status 'OK' -Detail "Coleta registrada em $gpresultPath" -Penalty 0
    }
    catch {
        Add-AdCheck -Category 'GPO' -Name 'gpresult' -Status 'AVISO' -Detail $_.Exception.Message -Penalty 5
    }
}

$summary = Get-AdHealthSummary
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Resumo AD - $($summary.Label)" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Reputação : $($summary.Score)/100" -ForegroundColor Yellow
Write-Host "Críticas  : $($summary.CriticalCount)" -ForegroundColor Yellow
Write-Host "Avisos    : $($summary.WarningCount)" -ForegroundColor Yellow
Write-Host ''

Write-AdReport -Summary $summary

if ($Modo -eq 'Assistido' -and $Canal) {
    $secureFail = @($script:Checks | Where-Object { $_.Nome -eq 'Canal seguro' -and $_.Status -eq 'FALHA' })
    if ($secureFail.Count -gt 0) {
        Write-Host ''
        Write-Warn 'O canal seguro ainda está quebrado.'
        if (Read-YesNo -Question 'Deseja tentar reparo guiado da conta de máquina agora?' -DefaultYes $true) {
            $cred = Get-Credential -Message 'Credencial de domínio para reparar a conta de máquina'
            try {
                if ([string]::IsNullOrWhiteSpace($script:TargetDc)) {
                    Reset-ComputerMachinePassword -Credential $cred -ErrorAction Stop
                }
                else {
                    Reset-ComputerMachinePassword -Server $script:TargetDc -Credential $cred -ErrorAction Stop
                }
                Write-Ok 'Reparo da conta de máquina executado.'
            }
            catch {
                Write-Fail "Falha no reparo guiado: $($_.Exception.Message)"
            }
        }
    }
}

Write-Info "Relatório texto: $script:TextReportPath"
if ($GerarHtml) {
    Write-Info "Relatório HTML : $script:HtmlReportPath"
    if ($AbrirRelatorio) {
        try { Start-Process $script:HtmlReportPath | Out-Null } catch { }
    }
}

if ($summary.CriticalCount -gt 0) {
    exit 2
}
elseif ($summary.WarningCount -gt 0) {
    exit 1
}
else {
    exit 0
}
