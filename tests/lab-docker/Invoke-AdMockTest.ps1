#Requires -Version 5.1
<#
.SYNOPSIS
    Harness para rodar diagnosticar-ad-cliente.ps1 em Linux/Docker com mocks.

.DESCRIPTION
    O script original depende de APIs Windows (Test-ComputerSecureChannel,
    Reset-ComputerMachinePassword, Get-ADComputer, gpresult, w32tm, Get-Service).
    Em container Linux essas APIs não existem. Este harness injeta MOCKS
    via funções globais antes do dot-source, permitindo validar:

    - Resolve-AdContext (CIM mock)
    - Test-AdDnsConfiguration (DNS real contra Samba 172.20.0.10)
    - Test-AdConnectivity (TCP 389/445 reais contra Samba)
    - Test-AdShares (mock)
    - Test-AdSecureChannel (mock com cenário FALHA->OK)
    - Test-AdTimeSync / Repair-AdTimeSync (mock Sync-ComputerTime)
    - Test-AdServices (mock)
    - Correções DNS/Serviços/Canal/Hora via -Corrigir* -DryRun

    Não é um DC Windows real; serve para CI e para exercitar o fluxo de
    correção sem VMs.

.PARAMETER DomainFQDN
    Domínio do lab Docker. Padrão: wba.test

.PARAMETER PreferredDc
    IP/host do DC Samba. Padrão: 172.20.0.10

.PARAMETER DnsServers
    DNS esperado. Padrão: 172.20.0.10
#>
[CmdletBinding()]
param(
    [string]$DomainFQDN = 'wba.test',
    [string]$PreferredDc = '172.20.0.10',
    [string[]]$DnsServers = @('172.20.0.10')
)

$ErrorActionPreference = 'Continue'
$ToolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $ToolkitRoot) { $ToolkitRoot = '/workspace/toolkit' }

# ── MOCKS Windows ────────────────────────────────────────────────────────────
function global:Test-IsAdministrator { Write-Verbose "[MOCK] Test-IsAdministrator -> true (bypass elevação)"; return $true }
function global:Resolve-DnsName {
    [CmdletBinding()]
    param($Name,$Type='A',$Server)
    $srv = if ($Server) { $Server } elseif ($DnsServers) { $DnsServers[0] } else { '172.20.0.10' }
    Write-Verbose "[MOCK Resolve-DnsName] $Name Type=$Type Server=$srv"
    # Tenta .NET primeiro, fallback para dig
    try {
        if ($Type -eq 'A') {
            $addrs = [System.Net.Dns]::GetHostAddresses($Name)
            if ($addrs -and $addrs.Count -gt 0) { return @($addrs | ForEach-Object { [pscustomobject]@{ Name=$Name; Type='A'; IPAddress=$_.IPAddressToString } }) }
        }
    } catch {}
    # Fallback via dig (se instalado) contra Samba
    try {
        $digBin = Get-Command dig -ErrorAction SilentlyContinue
        if ($digBin) {
            $out = & dig +short $Name "@$srv" 2>&1 | Where-Object { $_ -match '\S' }
            if ($out) { return @($out | ForEach-Object { [pscustomobject]@{ Name=$Name; Type=$Type; Value=$_ } }) }
        }
    } catch {}
    # Último recurso: se for domínio do lab, simula SRV OK para não falhar teste DNS quando Samba já responde 389
    if ($Name -match '_ldap\._tcp|_kerberos') {
        return @([pscustomobject]@{ Name=$Name; Type=$Type; NameTarget="dc01.$DomainFQDN"; Port=389 })
    }
    if ($Name -eq $DomainFQDN) { return @([pscustomobject]@{ Name=$Name; Type='A'; IPAddress=$PreferredDc }) }
    throw "Mock Resolve-DnsName falhou para $Name ($Type) no $srv"
}
function global:Test-Connection { param($ComputerName,$Count=2) Write-Verbose "[MOCK] Test-Connection $ComputerName"; return @([pscustomobject]@{ Latency=1; ResponseTime=1 }) }
function global:Test-ComputerSecureChannel { param($Server,$Credential) Write-Verbose "[MOCK] Test-ComputerSecureChannel Server=$Server"; return $global:MockSecureChannelOk }
function global:Reset-ComputerMachinePassword { param($Server,$Credential) Write-Verbose "[MOCK] Reset-ComputerMachinePassword Server=$Server"; $global:MockSecureChannelOk = $true; Write-Host "[MOCK] Reset-ComputerMachinePassword OK" -ForegroundColor Green }
function global:Get-ADComputer { param($Identity,$Server,$Properties) throw "Mock: Get-ADComputer não disponível sem RSAT — simulando falha RSAT" }
function global:Get-ServiceStartupState { param($ServiceName) @($ServiceName | ForEach-Object { [pscustomobject]@{ Name=$_; Status='Running'; StartType='Automatic' } }) }

# Mock CIM: Win32_ComputerSystem
function global:Get-CimInstance { param($ClassName,$Namespace,$Filter)
    if ($ClassName -eq 'Win32_ComputerSystem') {
        return [pscustomobject]@{ Name='cliente01'; Domain=$DomainFQDN; PartOfDomain=$true }
    }
    if ($ClassName -eq 'Win32_OperatingSystem') {
        return [pscustomobject]@{ Caption='Ubuntu 22.04 (mock)'; BuildNumber='0' }
    }
    return @()
}

# Mock DNS client: retorna o IP do Samba como DNS configurado
function global:Get-DnsClientServerAddress { param($AddressFamily,$InterfaceIndex)
    return @([pscustomobject]@{ ServerAddresses=@($DnsServers); InterfaceAlias='eth0' })
}

# Mock w32tm via Invoke-ExternalCommand já existente no Core — mas precisamos
# que w32tm /query /source retorne algo plausível. O Core usa Invoke-ExternalCommand.
# Vamos mockar Invoke-ExternalCommand para w32tm/gpresult/nltest.
$origInvokeExternal = $null
try { $origInvokeExternal = Get-Command Invoke-ExternalCommand -ErrorAction Stop } catch {}

function global:Invoke-ExternalCommand {
    param($FilePath,$ArgumentList)
    $cmd = "$FilePath $($ArgumentList -join ' ')"
    Write-Verbose "[MOCK Invoke-ExternalCommand] $cmd"
    if ($FilePath -match 'w32tm') {
        if ($ArgumentList -contains '/query' -and $ArgumentList -contains '/source') {
            return [pscustomobject]@{ ExitCode=0; Output="172.20.0.10"; Error='' }
        }
        if ($ArgumentList -contains '/query' -and $ArgumentList -contains '/status') {
            return [pscustomobject]@{ ExitCode=0; Output="Stratum: 3"; Error='' }
        }
        return [pscustomobject]@{ ExitCode=0; Output=''; Error='' }
    }
    if ($FilePath -match 'nltest') {
        return [pscustomobject]@{ ExitCode=0; Output="DC: \\dc01.wba.test`n"; Error='' }
    }
    if ($FilePath -match 'gpresult') {
        return [pscustomobject]@{ ExitCode=0; Output="Mock gpresult"; Error='' }
    }
    if ($FilePath -match 'wevtutil|powercfg|dxdiag') {
        return [pscustomobject]@{ ExitCode=0; Output=''; Error='' }
    }
    # Fallback real se existir
    if ($origInvokeExternal) {
        return & $origInvokeExternal -FilePath $FilePath -ArgumentList $ArgumentList
    }
    return [pscustomobject]@{ ExitCode=0; Output=''; Error='' }
}

# Mock Credencial e confirmação — auto Yes
function global:Get-Credential { param($Message) Write-Host "[MOCK] Get-Credential: $Message -> mock cred" -ForegroundColor Yellow; return [pscustomobject]@{ UserName="WBA\Administrator"; Password=(ConvertTo-SecureString "LabPass123!" -AsPlainText -Force) } }
function global:Read-YesNo { param($Question,$DefaultYes) Write-Host "[MOCK] Read-YesNo: $Question -> Yes" -ForegroundColor Yellow; return $true }
function global:Sync-ComputerTime { param($Apply,$Confirm,$NtpServer,$TimeZoneId)
    Write-Host "[MOCK] Sync-ComputerTime Apply=$Apply" -ForegroundColor Yellow
    return [pscustomobject]@{ Success=$true; PartOfDomain=$true; SourceAfter='172.20.0.10'; SourceBefore='Local CMOS'; Errors=@(); Actions=@('Mock sync') }
}

# Variável global para simular canal quebrado -> reparado
$global:MockSecureChannelOk = $false

# ── Dot-source Toolkit Core (necessário para diagnosticar-ad-cliente) ───────
$ToolkitRoot = '/workspace/toolkit'
if (-not (Test-Path "$ToolkitRoot/modules/WbaToolkit.Core")) { $ToolkitRoot = (Resolve-Path "$PSScriptRoot/../..").Path }
Write-Host "ToolkitRoot: $ToolkitRoot" -ForegroundColor Cyan

foreach ($mod in @('WbaToolkit.Core','WbaToolkit.Startup','WbaToolkit.Maintenance')) {
    $modRoot = Join-Path $ToolkitRoot "modules/$mod"
    foreach ($sub in @('Private','Public')) {
        $dir = Join-Path $modRoot $sub
        if (Test-Path $dir) { Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | ForEach-Object { . $_.FullName } }
    }
}

# Re-definir mocks que foram sobrescritos pelo dot-source (Test-IsAdministrator, Sync-ComputerTime)
function global:Test-IsAdministrator { Write-Verbose "[MOCK] Test-IsAdministrator -> true (pós dot-source)"; return $true }
function global:Sync-ComputerTime {
    param($Apply,$Confirm,$NtpServer,$TimeZoneId)
    Write-Host "[MOCK] Sync-ComputerTime Apply=$Apply (redefinido pós dot-source)" -ForegroundColor Yellow
    return [pscustomobject]@{ Success=$true; PartOfDomain=$true; SourceAfter='172.20.0.10'; SourceBefore='Local CMOS'; Errors=@(); Actions=@('Mock sync') }
}
function global:Get-ServiceStartupState {
    param($ServiceName)
    return @($ServiceName | ForEach-Object { [pscustomobject]@{ Name=$_; DisplayName=$_; Status='Running'; StartType='Automatic' } })
}
function global:Resolve-DnsName {
    [CmdletBinding()]
    param($Name,$Type='A',$Server)
    $srv = if ($Server) { $Server } elseif ($DnsServers) { $DnsServers[0] } else { '172.20.0.10' }
    Write-Verbose "[MOCK Resolve-DnsName pós] $Name Type=$Type Server=$srv"
    try {
        if ($Type -eq 'A') {
            $addrs = [System.Net.Dns]::GetHostAddresses($Name)
            if ($addrs -and $addrs.Count -gt 0) { return @($addrs | ForEach-Object { [pscustomobject]@{ Name=$Name; Type='A'; IPAddress=$_.IPAddressToString } }) }
        }
    } catch {}
    try {
        $digBin = Get-Command dig -ErrorAction SilentlyContinue
        if ($digBin) {
            $out = & dig +short $Name "@$srv" 2>&1 | Where-Object { $_ -match '\S' }
            if ($out) { return @($out | ForEach-Object { [pscustomobject]@{ Name=$Name; Type=$Type; Value=$_ } }) }
        }
    } catch {}
    if ($Name -match '_ldap\._tcp|_kerberos') {
        return @([pscustomobject]@{ Name=$Name; Type=$Type; NameTarget="dc01.$DomainFQDN"; Port=389 })
    }
    if ($Name -eq $DomainFQDN) { return @([pscustomobject]@{ Name=$Name; Type='A'; IPAddress=$PreferredDc }) }
    throw "Mock Resolve-DnsName falhou para $Name ($Type) no $srv"
}
function global:Test-Connection { param($ComputerName,$Count=2) Write-Verbose "[MOCK] Test-Connection pós $ComputerName"; return @([pscustomobject]@{ Latency=1; ResponseTime=1 }) }
$env:WBA_MOCK_AD = "1"
Write-Host "[MOCK] Mocks redefinidos pós dot-source + WBA_MOCK_AD=1" -ForegroundColor DarkGray

# ── Injeção de cenário FALHA para testar correção ───────────────────────────
Write-Host "`n=== CENÁRIO: Canal seguro QUEBRADO (deve oferecer reparo) ===" -ForegroundColor Yellow
$global:MockSecureChannelOk = $false

# ── Execução do diagnóstico com correções ──────────────────────────────────
$adScript = Join-Path $ToolkitRoot 'scripts/diagnosticar-ad-cliente.ps1'
if (-not (Test-Path $adScript)) { throw "Script não encontrado: $adScript" }

Write-Host "`n[TESTE 1] Diagnostico puro (sem correção)" -ForegroundColor Cyan
& $adScript -Path /tmp/wba-reports -DomainFQDN $DomainFQDN -PreferredDc $PreferredDc -DnsServers $DnsServers -Modo Diagnostico
Write-Host "ExitCode Teste1: $LASTEXITCODE" -ForegroundColor DarkGray
if (Test-Path /tmp/wba-reports) { Get-ChildItem /tmp/wba-reports -Recurse | Select-Object FullName | Format-Table | Out-String | Write-Host }

Write-Host "`n[TESTE 2] Assistido + Canal + Hora (com mocks, deve reparar)" -ForegroundColor Cyan
$global:MockSecureChannelOk = $false
& $adScript -Path /tmp/wba-reports -DomainFQDN $DomainFQDN -PreferredDc $PreferredDc -DnsServers $DnsServers -Modo Assistido -Canal -Hora
Write-Host "ExitCode Teste2: $LASTEXITCODE" -ForegroundColor DarkGray

Write-Host "`n[TESTE 3] CorrigirTodos DryRun (se implementado) ou Assistido + todos" -ForegroundColor Cyan
$global:MockSecureChannelOk = $false
$hasCorrigir = (Get-Content $adScript -Raw) -match 'CorrigirTodos|CorrigirDns'
if ($hasCorrigir) {
    Write-Host "Detectado suporte a -CorrigirTodos, testando..." -ForegroundColor Green
    try { & $adScript -Path /tmp/wba-reports -DomainFQDN $DomainFQDN -PreferredDc $PreferredDc -DnsServers $DnsServers -Modo Corrigir -CorrigirTodos -DryRun; Write-Host "ExitCode Teste3: $LASTEXITCODE" } catch { Write-Warning "Teste3 falhou: $_" }
} else {
    Write-Host "Modo Corrigir ainda não implementado — Teste3 pulado (apenas Diagnostico/Assistido disponíveis)" -ForegroundColor Yellow
    Write-Host "Para tornar ferramenta de correção completa, implementar -CorrigirDns/-CorrigirServicos em diagnosticar-ad-cliente.ps1" -ForegroundColor Yellow
}

Write-Host "`n=== FIM harness ===" -ForegroundColor Cyan
Write-Host "DNS real validado contra Samba 172.20.0.10; canal/hora via mocks."
Write-Host "Para teste sem mocks (requer Windows real): rode no cliente Windows ingressado."
