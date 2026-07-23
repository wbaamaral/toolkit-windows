<#
.SYNOPSIS
    Fase 1 do lab de AD: instala AD DS + DNS e promove a maquina a Controlador
    de Dominio (cria a floresta). A maquina REINICIA ao final.

.DESCRIPTION
    Executar em um Windows Server LIMPO, com PowerShell elevado.
    Apos o reboot, rodar 02-Configure-DC.ps1.

.PARAMETER DomainName
    FQDN do dominio a criar. Padrao: wba.test

.PARAMETER DomainNetbios
    Nome NetBIOS. Padrao: WBA

.PARAMETER StaticIp
    IP estatico do DC. Se vazio, mantem a configuracao atual de rede.

.PARAMETER PrefixLength
    Mascara (CIDR). Padrao: 24

.PARAMETER Gateway
    Gateway padrao. Use o mesmo da sua rede de testes.

.PARAMETER InterfaceAlias
    Nome do adaptador. Padrao: Ethernet

.EXAMPLE
    .\01-Provision-DC.ps1 -StaticIp 192.168.4.10 -Gateway 192.168.5.1
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DomainName    = 'wba.test',
    [string]$DomainNetbios = 'WBA',
    [string]$StaticIp      = '',
    [int]$PrefixLength     = 24,
    [string]$Gateway       = '',
    [string]$InterfaceAlias = 'Ethernet'
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Execute este script como Administrador.' }

# 1) IP estatico (opcional) — o DC deve usar a SI MESMO como DNS
if (-not [string]::IsNullOrWhiteSpace($StaticIp)) {
    Write-Host "Configurando IP estatico $StaticIp/$PrefixLength em '$InterfaceAlias'..." -ForegroundColor Cyan
    Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.PrefixOrigin -ne 'WellKnown' } |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    $params = @{
        InterfaceAlias = $InterfaceAlias
        IPAddress      = $StaticIp
        PrefixLength   = $PrefixLength
        AddressFamily  = 'IPv4'
    }
    if (-not [string]::IsNullOrWhiteSpace($Gateway)) { $params['DefaultGateway'] = $Gateway }
    New-NetIPAddress @params | Out-Null
}
# DNS do DC = ele mesmo (loopback)
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses '127.0.0.1'

# 2) Roles
Write-Host 'Instalando AD DS + DNS...' -ForegroundColor Cyan
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null

# 3) Promocao a DC (floresta nova) — REINICIA ao final
Import-Module ADDSDeployment
$dsrm = Read-Host -AsSecureString 'Defina a senha do DSRM (Directory Services Restore Mode)'
Write-Host "Promovendo a DC do dominio $DomainName (a maquina vai reiniciar)..." -ForegroundColor Yellow
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetbios `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -Force
