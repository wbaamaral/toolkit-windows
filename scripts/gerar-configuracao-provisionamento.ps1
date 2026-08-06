#Requires -Version 5.1
<#
.SYNOPSIS
    Assistente interativo que gera um provisioning.json para o WbaToolkit.Provisioning.

.DESCRIPTION
    Faz perguntas guiadas (computador, rede, discos, acesso remoto, contas locais,
    ativacao e politica de execucao) e monta um provisioning.json valido conforme
    SPEC-PROVISIONING-CONFIG e o schema modules/WbaToolkit.Provisioning/Schemas/
    provisioning-config-v1.schema.json.

    Nao altera o sistema: apenas escreve o arquivo JSON de saida. Ao final, se o
    modulo WbaToolkit.Provisioning estiver disponivel, valida o resultado com
    Test-ToolkitProvisioningConfig (tambem sem efeito no sistema).

    Segredos (senha de conta, chave de ativacao) NUNCA sao digitados aqui: o
    assistente so pergunta o nome do secretRef que sera resolvido depois, em
    tempo de execucao, por um provedor configurado (ver
    spec/modulos/provisioning/04-seguranca-segredos.md).

    Secoes cobertas: computer, network, storage, remoteAccess, accounts,
    activation, policy. Certificados, regras de firewall avancadas, sysprep e
    extensions nao tem assistente ainda — edite o JSON gerado manualmente para
    essas secoes, se precisar.

.PARAMETER OutputPath
    Caminho do arquivo JSON de saida. Padrao: .\provisioning.json.

.PARAMETER Help
    Exibe esta ajuda e encerra.

.EXAMPLE
    .\gerar-configuracao-provisionamento.ps1

.EXAMPLE
    .\gerar-configuracao-provisionamento.ps1 -OutputPath C:\WBA\Provisioning\provisioning.json

.NOTES
    Projeto: wba-windows-toolkit
    Autor: wbaamaral
    Nao requer privilegios de Administrador: so escreve um arquivo local.
    Modulos: WbaToolkit.Core (obrigatorio); WbaToolkit.Provisioning (opcional,
    usado apenas para validar o resultado ao final).
#>
[CmdletBinding()]
param(
    [string]$OutputPath = '.\provisioning.json',

    [switch]$Help
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null }
catch { Write-Verbose "Nao foi possivel ajustar a pagina de codigo do console para UTF-8: $($_.Exception.Message)" }

$ScriptVersion = 'v1.0.0'
$ScriptName    = if ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } else { Split-Path -Leaf $PSCommandPath }

function Show-Help {
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "Assistente de Configuracao de Provisionamento — $script:ScriptVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uso:  .\$script:ScriptName [opcoes]"
    Write-Host ""
    Write-Host "  -OutputPath '<arquivo>'  Caminho do JSON de saida. Padrao: .\provisioning.json."
    Write-Host "  -Help                    Esta ajuda."
    Write-Host ""
    Write-Host "Faz perguntas sobre computador, rede, discos, acesso remoto, contas locais,"
    Write-Host "ativacao e politica de execucao, e gera o provisioning.json. Segredos nunca"
    Write-Host "sao digitados aqui — so o nome do secretRef que sera resolvido depois."
    Write-Host ""
    Write-Host "Exemplos:"
    Write-Host "  .\$script:ScriptName"
    Write-Host "  .\$script:ScriptName -OutputPath C:\WBA\Provisioning\provisioning.json"
    Write-Host ""
}

if ($Help) { Show-Help; exit 0 }

# === Dependencias: dot-source direto (ADR 0032) ===
$ToolkitRoot    = Split-Path -Parent $PSScriptRoot
$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'

if (-not (Test-Path -LiteralPath $coreModuleRoot)) {
    throw "Modulo nao encontrado: $coreModuleRoot"
}

try {
    foreach ($sub in @('Private', 'Public')) {
        $dir = Join-Path $coreModuleRoot $sub
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
        }
    }
}
catch {
    throw "Nao foi possivel carregar WbaToolkit.Core: $($_.Exception.Message)"
}

# WBA-DOCS: Category=Provisioning; Manual=Assistente interativo para gerar provisioning.json

$ErrorActionPreference = 'Stop'

# ─── helpers locais de prompt ─────────────────────────────────────────────────

function Read-PatternInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Question,
        [string]$DefaultValue,
        [string]$Pattern,
        [string]$PatternHint,
        [switch]$AllowEmpty
    )
    while ($true) {
        $value = if ($DefaultValue) { Read-UserInput -Question $Question -DefaultValue $DefaultValue } else { Read-UserInput -Question $Question }
        if ([string]::IsNullOrWhiteSpace($value)) {
            if ($AllowEmpty -or $DefaultValue) { return $value }
            Write-Warn 'Valor obrigatorio.'
            continue
        }
        if (-not $Pattern -or $value -match $Pattern) { return $value }
        $hintSuffix = if ($PatternHint) { " ($PatternHint)" } else { '' }
        Write-Warn "Valor invalido$hintSuffix. Tente novamente."
    }
}

function Read-ChoiceInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Question,
        [Parameter(Mandatory)][string[]]$Options,
        [string]$DefaultValue
    )
    $optionsText = $Options -join '/'
    while ($true) {
        $value = Read-PatternInput -Question "$Question ($optionsText)" -DefaultValue $DefaultValue
        if ($Options -contains $value) { return $value }
        Write-Warn "Escolha uma das opcoes: $optionsText."
    }
}

function Read-ProfileListInput {
    [CmdletBinding()]
    param(
        [string]$DefaultValue = 'Private'
    )
    $allowed = @('Domain', 'Private', 'Public')
    while ($true) {
        $raw = Read-UserInput -Question "Perfis de firewall, separados por virgula ($($allowed -join '/'))" -DefaultValue $DefaultValue
        $items = @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $invalid = @($items | Where-Object { $allowed -notcontains $_ })
        # ,$items (nao so $items): sem a virgula, um array de 1 elemento e desenrolado
        # para escalar ao passar pelo pipeline de retorno da funcao.
        if ($invalid.Count -eq 0 -and $items.Count -gt 0) { return , $items }
        Write-Warn "Perfis invalidos: $($invalid -join ', '). Use apenas $($allowed -join '/')."
    }
}

# ─── inicio do assistente ─────────────────────────────────────────────────────

Write-Title 'Assistente de Configuracao de Provisionamento'
Write-Info 'Respostas em branco (ENTER) usam o valor padrao entre colchetes, quando houver.'
Write-Info 'Nada e alterado no sistema; apenas o arquivo JSON de saida e escrito.'

$config = [ordered]@{
    '$schema'      = 'https://schemas.wba.local/windows-toolkit/provisioning/v1.json'
    schemaVersion  = 1
    deploymentId   = Read-PatternInput -Question 'Identificador do deployment (deploymentId)' `
        -Pattern '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' `
        -PatternHint 'inicia com letra/numero; apenas letras, numeros, ponto, hifen e underscore'
}

# --- computer -------------------------------------------------------------
Write-Section 'Computador'
if (Read-YesNo -Question 'Configurar nome do computador e fuso horario?' -DefaultYes $true) {
    $computer = [ordered]@{}
    $name = Read-PatternInput -Question 'Nome do computador (NetBIOS, ate 15 caracteres)' -AllowEmpty `
        -Pattern '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$' `
        -PatternHint 'inicia com letra/numero; letras, numeros e hifen; maximo 15 caracteres'
    if ($name) { $computer.name = $name }
    $timeZone = Read-UserInput -Question 'ID do fuso horario Windows (ex.: SA Western Standard Time)' -DefaultValue 'SA Western Standard Time'
    if ($timeZone) { $computer.timeZone = $timeZone }
    if ($computer.Count -gt 0) { $config.computer = $computer }
}

# --- network ---------------------------------------------------------------
Write-Section 'Rede'
if (Read-YesNo -Question 'Configurar algum adaptador de rede?' -DefaultYes $false) {
    $adapters = @()
    do {
        $adapter = [ordered]@{ name = Read-PatternInput -Question 'Nome descritivo do adaptador' -DefaultValue 'Rede Corporativa' }

        $matchType = Read-ChoiceInput -Question 'Identificar o adaptador por' -Options @('mac', 'pnp', 'alias') -DefaultValue 'mac'
        $match = [ordered]@{}
        switch ($matchType) {
            'mac'   { $match.macAddress   = Read-PatternInput -Question 'Endereco MAC (ex.: 00-50-56-96-1D-27)' -Pattern '^[0-9A-Fa-f]{2}([-:][0-9A-Fa-f]{2}){5}$' -PatternHint 'formato XX-XX-XX-XX-XX-XX' }
            'pnp'   { $match.pnpDeviceId  = Read-PatternInput -Question 'PnP Device ID' }
            'alias' { $match.alias        = Read-PatternInput -Question 'Alias/nome da interface (ex.: Ethernet0)' }
        }
        $adapter.match = $match

        $dhcp = Read-YesNo -Question 'Usar DHCP neste adaptador?' -DefaultYes $false
        $adapter.dhcp = $dhcp
        if (-not $dhcp) {
            $addressesRaw = Read-PatternInput -Question 'Enderecos IP com prefixo CIDR, separados por virgula (ex.: 192.168.4.118/24)'
            $adapter.addresses = @($addressesRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $adapter.gateway = Read-PatternInput -Question 'Gateway'
            $dnsRaw = Read-UserInput -Question 'Servidores DNS, separados por virgula' -DefaultValue ''
            if ($dnsRaw) { $adapter.dnsServers = @($dnsRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        }

        $adapters += [pscustomobject]$adapter
    } while (Read-YesNo -Question 'Adicionar outro adaptador?' -DefaultYes $false)

    $config.network = [ordered]@{ adapters = $adapters }
}

# --- storage -----------------------------------------------------------------
Write-Section 'Discos'
if (Read-YesNo -Question 'Configurar algum disco adicional (inicializar/particionar/formatar)?' -DefaultYes $false) {
    $disks = @()
    do {
        $disk = [ordered]@{ name = Read-PatternInput -Question 'Nome descritivo do disco' -DefaultValue 'dados01' }

        $matchType = Read-ChoiceInput -Question 'Identificar o disco por' -Options @('serial', 'uniqueid', 'localizacao') -DefaultValue 'serial'
        $match = [ordered]@{}
        switch ($matchType) {
            'serial'      { $match.serialNumber = Read-PatternInput -Question 'Numero de serie do disco' }
            'uniqueid'    { $match.uniqueId     = Read-PatternInput -Question 'Unique ID do disco' }
            'localizacao' {
                $match.busType   = Read-PatternInput -Question 'Tipo de barramento (ex.: SCSI, SAS, NVMe)'
                $match.location  = Read-PatternInput -Question 'Localizacao (ex.: PCI Slot 11)'
                $match.sizeBytes = [int64](Read-PatternInput -Question 'Tamanho aproximado em bytes' -Pattern '^\d+$' -PatternHint 'somente numeros')
            }
        }
        $disk.match = $match

        $disk.fileSystem = Read-ChoiceInput -Question 'Sistema de arquivos' -Options @('NTFS', 'ReFS') -DefaultValue 'NTFS'
        $driveLetter = Read-PatternInput -Question 'Letra de unidade (D-Z)' -AllowEmpty -Pattern '^[D-Zd-z]$' -PatternHint 'uma unica letra entre D e Z'
        if ($driveLetter) { $disk.driveLetter = $driveLetter.ToUpperInvariant() }
        $label = Read-UserInput -Question 'Rotulo do volume' -DefaultValue $disk.name
        if ($label) { $disk.label = $label }

        $disks += [pscustomobject]$disk
    } while (Read-YesNo -Question 'Adicionar outro disco?' -DefaultYes $false)

    $config.storage = [ordered]@{ disks = $disks }

    Write-Warn "Discos declarados exigem 'policy.allowDestructiveStorage: true' para serem tocados de fato."
    Write-Warn 'Sem essa politica explicita, a etapa storage.configure recusa qualquer alteracao.'
    $allowDestructive = $false
    if (Read-YesNo -Question 'Autorizar operacoes destrutivas de disco neste documento?' -DefaultYes $false) {
        $confirmation = Read-UserInput -Question "Digite exatamente 'sim autorizo seguir' para confirmar"
        if ($confirmation -eq 'sim autorizo seguir') {
            $allowDestructive = $true
        }
        else {
            Write-Warn 'Confirmacao nao corresponde; allowDestructiveStorage permanece false.'
        }
    }
}

# --- remoteAccess --------------------------------------------------------------
Write-Section 'Acesso remoto (RDP / WinRM)'
$remoteAccess = [ordered]@{}
if (Read-YesNo -Question 'Configurar RDP (Area de Trabalho Remota)?' -DefaultYes $false) {
    $rdp = [ordered]@{ enabled = Read-YesNo -Question 'Habilitar RDP?' -DefaultYes $true }
    $rdp.firewallProfile = Read-ProfileListInput -DefaultValue 'Private'
    $remoteAccess.rdp = $rdp
}
if (Read-YesNo -Question 'Configurar WinRM (gerenciamento remoto)?' -DefaultYes $false) {
    $winrm = [ordered]@{ enabled = Read-YesNo -Question 'Habilitar WinRM?' -DefaultYes $true }
    if ($winrm.enabled) {
        $winrm.certificateThumbprint = Read-PatternInput -Question 'Thumbprint do certificado ja declarado para WinRM HTTPS' -Pattern '^[0-9A-Fa-f]{40}$' -PatternHint '40 caracteres hexadecimais'
    }
    $winrm.firewallProfile = Read-ProfileListInput -DefaultValue 'Private'
    $remoteAccess.winrm = $winrm
}
if ($remoteAccess.Count -gt 0) { $config.remoteAccess = $remoteAccess }

# --- accounts --------------------------------------------------------------
Write-Section 'Contas locais'
if (Read-YesNo -Question 'Configurar alguma conta local?' -DefaultYes $false) {
    $accounts = @()
    do {
        $account = [ordered]@{ name = Read-PatternInput -Question 'Nome da conta' }
        $account.ensure = Read-ChoiceInput -Question 'Estado desejado' -Options @('Present', 'Absent') -DefaultValue 'Present'

        if ($account.ensure -eq 'Present') {
            if (Read-YesNo -Question 'Definir senha via secretRef (necessario para conta nova)?' -DefaultYes $true) {
                $secretRef = Read-PatternInput -Question 'Nome do secretRef (a senha em si NAO e digitada aqui)'
                $account.password = [ordered]@{ secretRef = $secretRef }
            }
            $groupsRaw = Read-UserInput -Question 'Grupos locais, separados por virgula (ex.: Administrators)' -DefaultValue ''
            if ($groupsRaw) { $account.groups = @($groupsRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        }

        $accounts += [pscustomobject]$account
    } while (Read-YesNo -Question 'Adicionar outra conta?' -DefaultYes $false)

    $config.accounts = $accounts
}

# --- activation --------------------------------------------------------------
Write-Section 'Ativacao do Windows'
if (Read-YesNo -Question 'Configurar instalacao de chave de produto?' -DefaultYes $false) {
    $activation = [ordered]@{}
    $activation.productKeySecretRef = Read-PatternInput -Question 'Nome do secretRef da chave de produto (a chave em si NAO e digitada aqui)'
    $activation.partialProductKey   = Read-PatternInput -Question 'Ultimos 5 caracteres da chave (visiveis em qualquer diagnostico)' `
        -Pattern '^[A-Za-z0-9]{5}$' -PatternHint 'exatamente 5 letras/numeros'
    $config.activation = $activation
}

# --- policy --------------------------------------------------------------
Write-Section 'Politica de execucao'
$policy = [ordered]@{
    onError             = Read-ChoiceInput -Question 'Comportamento em erro' -Options @('Stop', 'Continue') -DefaultValue 'Stop'
    maxAttemptsPerStep  = [int](Read-PatternInput -Question 'Tentativas maximas por etapa' -DefaultValue '3' -Pattern '^\d+$' -PatternHint 'somente numeros')
    reboot              = Read-ChoiceInput -Question 'Reinicializacao' -Options @('Never', 'WhenRequired', 'Manual') -DefaultValue 'WhenRequired'
    cleanup             = Read-ChoiceInput -Question 'Limpeza ao concluir' -Options @('RemoveSecretsAndConfig', 'RemoveSecretsOnly', 'RetainAll') -DefaultValue 'RemoveSecretsAndConfig'
}
if ($config.Contains('storage')) {
    $policy.allowDestructiveStorage = $allowDestructive
}
$config.policy = $policy

# ─── escrita do arquivo ────────────────────────────────────────────────────────

Write-Section 'Gravando arquivo'

if ((Test-Path -LiteralPath $OutputPath) -and -not (Read-YesNo -Question "'$OutputPath' ja existe. Sobrescrever?" -DefaultYes $false)) {
    Write-Warn 'Operacao cancelada pelo operador.'
    exit 1
}

$json = $config | ConvertTo-Json -Depth 12
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.File]::WriteAllText($resolvedOutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Ok "Arquivo gravado: $resolvedOutputPath"

# ─── validacao best-effort (nao altera o sistema) ──────────────────────────────

$corePsd1         = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$provisioningPsd1 = Join-Path $ToolkitRoot 'modules/WbaToolkit.Provisioning/WbaToolkit.Provisioning.psd1'
if (Test-Path -LiteralPath $provisioningPsd1) {
    try {
        # Import-Module (nao apenas dot-source) porque WbaToolkit.Provisioning declara
        # RequiredModules = @('WbaToolkit.Core') no psd1 — o sistema de modulos precisa
        # do WbaToolkit.Core registrado como modulo carregado, nao so das funcoes disponiveis.
        Import-Module $corePsd1 -Force -ErrorAction Stop
        Import-Module $provisioningPsd1 -Force -ErrorAction Stop
        $validation = Test-ToolkitProvisioningConfig -Path $resolvedOutputPath
        if ($validation.IsValid) {
            Write-Ok 'Configuracao valida (Test-ToolkitProvisioningConfig).'
        }
        else {
            Write-Fail 'Configuracao gerada NAO passou na validacao:'
            $validation.Errors | ForEach-Object { Write-Fail "  $_" }
        }
        if ($validation.Warnings) {
            $validation.Warnings | ForEach-Object { Write-Warn "  $_" }
        }
    }
    catch {
        Write-Warn "Nao foi possivel validar automaticamente: $($_.Exception.Message)"
        Write-Info "Valide manualmente com: Test-ToolkitProvisioningConfig -Path '$resolvedOutputPath'"
    }
}
else {
    Write-Info "WbaToolkit.Provisioning nao encontrado aqui; valide manualmente com: Test-ToolkitProvisioningConfig -Path '$resolvedOutputPath'"
}
