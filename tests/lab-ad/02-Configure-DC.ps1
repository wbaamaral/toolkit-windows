<#
.SYNOPSIS
    Fase 2 do lab de AD (rodar no DC APOS o reboot da fase 1): cria OU, usuario
    de teste e uma GPO linkada com conteudo, para que o gpresult tenha o que reportar.

.PARAMETER DomainName
    FQDN do dominio. Padrao: wba.test

.PARAMETER OuName
    Nome da OU de laboratorio. Padrao: WBA-Lab

.PARAMETER TestUser
    SamAccountName do usuario de teste. Padrao: lab.operador

.PARAMETER TestUserPassword
    Senha do usuario de teste (texto). Use uma forte; padrao apenas para lab.

.EXAMPLE
    .\02-Configure-DC.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DomainName       = 'wba.test',
    [string]$OuName           = 'WBA-Lab',
    [string]$TestUser         = 'lab.operador',
    [string]$TestUserPassword = 'P@ssw0rd-Lab-2026!'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Import-Module GroupPolicy

$domainDn = (Get-ADDomain -Identity $DomainName).DistinguishedName
$ouDn     = "OU=$OuName,$domainDn"

# OU de laboratorio
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$OuName'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $OuName -Path $domainDn -ProtectedFromAccidentalDeletion $false
    Write-Host "OU criada: $ouDn" -ForegroundColor Green
}

# Usuario de teste (para logar no cliente e rodar o gpresult de usuario)
if (-not (Get-ADUser -Filter "SamAccountName -eq '$TestUser'" -ErrorAction SilentlyContinue)) {
    $pw = ConvertTo-SecureString $TestUserPassword -AsPlainText -Force
    New-ADUser -Name $TestUser -SamAccountName $TestUser -AccountPassword $pw `
        -Enabled $true -Path $ouDn -ChangePasswordAtLogon $false
    Write-Host "Usuario criado: $TestUser" -ForegroundColor Green
}

# GPO linkada com uma chave de registro (para o gpresult exibir conteudo aplicado)
$gpoName = 'WBA Lab - Baseline'
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $gpoName
    New-GPLink -Name $gpoName -Target $domainDn | Out-Null
    Write-Host "GPO criada e linkada ao dominio: $gpoName" -ForegroundColor Green
}
Set-GPRegistryValue -Name $gpoName -Key 'HKLM\Software\Policies\WBA' `
    -ValueName 'LabMarker' -Type String -Value 'ok' | Out-Null

Write-Host "`nLab pronto. Dominio=$DomainName | OU=$ouDn | Usuario=$TestUser" -ForegroundColor Cyan
Write-Host 'Proximo: rodar 03-Join-Client.ps1 no cliente membro.' -ForegroundColor Cyan
