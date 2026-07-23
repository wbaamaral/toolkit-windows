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
Import-Module (Join-Path $ToolkitRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1') -Force -ErrorAction Stop

$ScriptVersion = 'v1.0.0'
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
                        Set-AdCheckResult -Category 'Domínio' -Name 'Canal seguro' -Status 'OK' -Detail 'Secure channel íntegro apos reparo.' -Penalty 0
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
        $sync = Sync-ComputerTime -Apply -Confirm:$false
        if ($sync.Success -and $sync.PartOfDomain -and $sync.SourceAfter -notmatch 'Local CMOS|Free-running') {
            Set-AdCheckResult -Category 'Tempo' -Name 'Sincronização de hora' -Status 'OK' -Detail "Sincronização corrigida. Fonte de tempo: $($sync.SourceAfter)" -Penalty 0
            Add-AdCheck -Category 'Tempo' -Name 'Reparo da hora' -Status 'OK' -Detail 'Reparo concluído pela rotina compartilhada de sincronização.' -Penalty 0
        }
        else {
            $detail = if ($sync.Errors.Count -gt 0) { $sync.Errors -join '; ' } else { "Fonte atual: $($sync.SourceAfter)" }
            Add-AdCheck -Category 'Tempo' -Name 'Reparo da hora' -Status 'FALHA' -Detail $detail -Recommendation 'Verifique conectividade com o DC e permissões de administrador.' -Penalty 10 -Critical
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
@font-face{font-family:'Inter';font-style:normal;font-weight:400;font-display:swap;src:local('Inter Regular'),local('Segoe UI'),local('sans-serif')}
@font-face{font-family:'Inter';font-style:normal;font-weight:700;font-display:swap;src:local('Inter Bold'),local('Segoe UI Bold'),local('sans-serif')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:400;font-display:swap;src:local('JetBrains Mono Regular'),local('Consolas'),local('monospace')}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:700;font-display:swap;src:local('JetBrains Mono Bold'),local('Consolas Bold'),local('monospace')}
:root{--primary:#1e3a5f;--primary-lt:#2d5986;--accent:#2563eb;--success:#16a34a;--warning:#d97706;--danger:#dc2626;--bg:#f0f4f8;--surface:#fff;--border:#e2e8f0;--text:#1e293b;--muted:#64748b;--radius:8px;--font-sans:'Inter','Segoe UI',system-ui,-apple-system,sans-serif;--font-mono:'JetBrains Mono','Consolas',ui-monospace,monospace}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:var(--font-sans);background:var(--bg);color:var(--text);font-size:14px;line-height:1.5}
h1{margin-bottom:4px;font-size:22px;font-weight:700;color:var(--text)}
h2{border-bottom:1px solid var(--border);padding-bottom:6px;margin-top:28px;font-size:16px;font-weight:700;color:var(--text)}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{border:1px solid var(--border);padding:8px;vertical-align:top}
th{background:#f8fafc;text-align:left;font-weight:600;font-size:11px;text-transform:uppercase;color:var(--muted)}
tr:nth-child(even){background:#fafafa}
code{font-family:var(--font-mono);font-size:12px;background:#f3f4f6;padding:2px 5px;border-radius:4px}
.muted{color:var(--muted)}
.small{font-size:11px}
.nowrap{white-space:nowrap}
.page{max-width:1120px;margin:24px auto;padding:32px;background:var(--surface);box-shadow:0 10px 15px rgba(0,0,0,.08);border-radius:var(--radius)}
.toolbar{max-width:1120px;margin:24px auto 0;text-align:right}
button{border:0;border-radius:4px;background:var(--accent);color:#fff;cursor:pointer;font:inherit;padding:8px 14px}
button:hover{background:#1d4ed8}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:1rem;margin-bottom:1.5rem}
.card{background:var(--surface);border-radius:var(--radius);padding:1.1rem 1.25rem;box-shadow:0 1px 6px rgba(0,0,0,.07);border-left:4px solid var(--accent);transition:box-shadow .15s}
.card:hover{box-shadow:0 4px 14px rgba(0,0,0,.12)}
.card-icon{font-size:1.4rem;margin-bottom:.4rem}
.card-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:600}
.card-value{font-size:1.05rem;font-weight:700;color:var(--primary);margin-top:.2rem}
.card-sub{font-size:.75rem;color:var(--muted);margin-top:.15rem}
.card-val{font-size:26px;font-weight:700;color:var(--text)}
.card-ok{background:#f0fdf4;border-left-color:var(--success)}
.card-warn{background:#fffbeb;border-left-color:var(--warning)}
.card-danger{background:#fef2f2;border-left-color:var(--danger)}
.section{background:var(--surface);border-radius:var(--radius);box-shadow:0 1px 6px rgba(0,0,0,.07);margin-bottom:1.25rem;overflow:hidden}
.section-hdr{background:var(--primary);color:#fff;padding:.75rem 1.5rem;font-size:.9rem;font-weight:700;display:flex;align-items:center;gap:.5rem}
.section-body{padding:1.25rem 1.5rem}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}
.metric{background:#f9fafb;border-radius:8px;padding:12px;border:1px solid var(--border)}
.metric b{display:block;color:var(--muted);font-size:12px;text-transform:uppercase;margin-bottom:6px}
.badge{display:inline-block;border-radius:4px;padding:.15em .55em;font-size:.72rem;font-weight:700;white-space:nowrap}
.badge-green,.ok{background:#dcfce7;color:#166534}
.badge-yellow,.warn{background:#fef3c7;color:#92400e}
.badge-red,.danger{background:#fee2e2;color:#991b1b}
.badge-blue{background:#dbeafe;color:#1e40af}
.badge-gray{background:#f1f5f9;color:#475569}
.nivel-ok{background:#dcfce7;color:#166534}
.nivel-warn{background:#fef3c7;color:#92400e}
.nivel-danger{background:#fee2e2;color:#991b1b}
.nivel-na{background:#f3f4f6;color:var(--muted)}
.sig-ok{background:#dbeafe;color:#1e40af}
.sig-danger{background:#fee2e2;color:#991b1b}
.sig-na{background:#f3f4f6;color:var(--muted)}
.alert{background:#fffbeb;border:1px solid #fcd34d;padding:12px 16px;border-radius:6px;margin:12px 0}
.info-box{background:#f9fafb;border:1px solid var(--border);border-radius:8px;padding:16px}
.disk-bar{background:#e2e8f0;border-radius:4px;height:8px;min-width:80px;overflow:hidden}
.disk-fill{height:100%;border-radius:4px;transition:width .3s}
.bar-ok{background:var(--success)}
.bar-warn{background:var(--warning)}
.bar-danger{background:var(--danger)}
.summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:16px 0 24px}
.label{color:var(--muted);font-size:.9rem}
.value{font-size:1.3rem;font-weight:700}
.link-btn{display:inline-block;font-size:11px;font-weight:600;border:1px solid var(--border);border-radius:4px;padding:2px 5px;text-decoration:none;color:var(--text);margin:1px}
.link-btn:hover{background:#e5e7eb}
.link-vt{border-color:#bfdbfe;color:var(--accent)}
.link-vt:hover{background:#dbeafe}
.link-na{color:#9ca3af;border-color:var(--border)}
.rank{text-align:center;font-weight:700;color:var(--text)}
.path-cell{font-family:var(--font-mono);font-size:11px;word-break:break-all}
.meta{background:#f0f4f8;padding:12px 16px;border-radius:4px;margin-bottom:16px;font-size:12px}
tr.ok td{background:#e8f5e9}
tr.fail td{background:#ffebee}
tr.dryrun td{background:#fff9c4}
tr.ignored td{background:#f5f5f5;color:#888}
tr.warn td{background:#fffbeb}
tr.danger td{background:#fff1f2}
.filter-wrap{margin-bottom:.75rem;display:flex;gap:.5rem;align-items:center}
.filter-input{flex:1;max-width:400px;padding:.45rem .75rem;border:1px solid var(--border);border-radius:var(--radius);font-size:.85rem;color:var(--text);outline:none;transition:border-color .15s}
.filter-input:focus{border-color:var(--accent)}
.filter-count{font-size:.78rem;color:var(--muted)}
footer{text-align:center;color:var(--muted);font-size:.78rem;padding:1.5rem;margin-top:.5rem}
@page{size:A4;margin:15mm}
@media print{body{background:#fff;color:#000;font-size:11px}.toolbar,.filter-wrap{display:none}.page{max-width:none;margin:0;padding:0;box-shadow:none}header,.section-hdr{print-color-adjust:exact;-webkit-print-color-adjust:exact}*{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
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
    $relaunchCommand = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relaunchCommand) -Verb RunAs
    exit
}

$script:ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'diagnostico-ad'
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
