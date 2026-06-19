<#
.SYNOPSIS
    Fase 3 do lab de AD (rodar no CLIENTE membro): aponta o DNS para o DC,
    instala o RSAT AD PowerShell (necessario para Get-ADComputer) e ingressa
    a maquina no dominio. A maquina REINICIA ao final.

.PARAMETER DomainName
    FQDN do dominio. Padrao: wba.test

.PARAMETER DcIp
    IP do DC (vira o servidor DNS do cliente). Padrao: 192.168.4.10

.PARAMETER InterfaceAlias
    Nome do adaptador. Padrao: Ethernet

.EXAMPLE
    .\03-Join-Client.ps1 -DcIp 192.168.4.10
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DomainName     = 'wba.test',
    [string]$DcIp           = '192.168.4.10',
    [string]$InterfaceAlias = 'Ethernet'
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Execute este script como Administrador.' }

# 1) DNS do cliente = DC (passo CRITICO para localizar o dominio)
Write-Host "Apontando DNS de '$InterfaceAlias' para $DcIp..." -ForegroundColor Cyan
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DcIp

# 2) Validar resolucao do dominio antes de ingressar
Write-Host "Validando resolucao de $DomainName..." -ForegroundColor Cyan
$null = Resolve-DnsName -Name $DomainName -Type SRV -Server $DcIp -ErrorAction Stop

# 3) RSAT AD PowerShell (Get-ADComputer usado pelo Diagnostico-GPO-Client)
Write-Host 'Instalando RSAT ActiveDirectory PowerShell...' -ForegroundColor Cyan
$cap = Get-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools*' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($cap -and $cap.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}

# 4) Ingresso no dominio (pede credencial de Domain Admin) — REINICIA
Write-Host "Ingressando no dominio $DomainName (a maquina vai reiniciar)..." -ForegroundColor Yellow
$cred = Get-Credential -Message "Credencial de Domain Admin (ex.: WBA\Administrator)"
Add-Computer -DomainName $DomainName -Credential $cred -Restart -Force
