# =============================================================================
# [NAO VALIDADO] Script sem execucao real documentada em Windows.
# Nao recomendado para uso em producao ate validacao operacional.
# Registro: nao-validado/README.md
# =============================================================================
#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Diagnostica e corrige falhas de conta de máquina/canal seguro em domínio Active Directory.

.DESCRIPTION
    Executa uma sequência interativa de testes para validar DNS, registros SRV do AD, descoberta de DC,
    portas essenciais, sincronização de hora, ingresso no domínio, canal seguro da conta de máquina,
    tickets Kerberos da conta de computador e reparo do secure channel.

    O script não altera configurações críticas sem confirmação do operador.

.EXAMPLE
    .\Testa-Repara-ContaMaquinaAD.ps1

.EXAMPLE
    .\Testa-Repara-ContaMaquinaAD.ps1 -DomainFqdn contoso.local -DomainNetBIOS NOVALAMMY -PreferredDc 192.168.1.7

.EXAMPLE
    .\Testa-Repara-ContaMaquinaAD.ps1 -DomainFqdn contoso.local -DnsServers 192.168.1.7
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainFqdn,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainNetBIOS,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PreferredDc,

    [Parameter(Mandatory = $false)]
    [string[]]$DnsServers,

    [Parameter(Mandatory = $false)]
    [switch]$NoTranscript,

    [Parameter(Mandatory = $false)]
    [Alias('DiretorioSaida')]
    [string]$Path
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
chcp 65001 | Out-Null

$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$ToolkitModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $ToolkitModulePath -Force -ErrorAction Stop

# WBA-DOCS: Category=ActiveDirectory; Related=Diagnostico-GPO-Client.ps1; Manual=Teste e reparo de conta de maquina no dominio AD

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot

$script:DomainCredential = $null
$script:Results = New-Object System.Collections.Generic.List[object]
$script:DetectedDcHost = $null
$script:DetectedDcIp = $null

function Add-TestResult {
    [CmdletBinding()]
    param(
        [string]$Etapa,
        [string]$Status,
        [string]$Detalhe
    )

    $script:Results.Add([PSCustomObject]@{
        DataHora = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Etapa    = $Etapa
        Status   = $Status
        Detalhe  = $Detalhe
    }) | Out-Null
}

function Read-ValueWithDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        [Parameter(Mandatory = $false)][string]$DefaultValue
    )
    return Read-UserInput -Question $Question -DefaultValue $DefaultValue
}

function Test-IsIPv4 {
    [CmdletBinding()]
    param([string]$Value)
    return ($Value -match '^\d{1,3}(\.\d{1,3}){3}$')
}

function Get-DomainCredentialSafe {
    [CmdletBinding()]
    param([string]$Purpose)

    if ($null -eq $script:DomainCredential) {
        $userHint = if (-not [string]::IsNullOrWhiteSpace($DomainNetBIOS)) {
            "$DomainNetBIOS\Administrador"
        }
        else {
            'DOMINIO\Administrador'
        }

        Write-Info "Será solicitada uma credencial com permissão para: $Purpose"
        Write-Info "Exemplo de formato: $userHint"
        $script:DomainCredential = Get-Credential -Message "Credencial de domínio para $Purpose"
    }

    return $script:DomainCredential
}

function Initialize-Log {
    [CmdletBinding()]
    param()
    if ($NoTranscript) {
        return
    }

    $session = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'ActiveDirectory'
    $logDir = $session.LogsPath
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $logFile = Join-Path $logDir ("AD-MachineAccount-Repair-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))

    try {
        Start-Transcript -Path $logFile -Force | Out-Null
        Write-Ok "Log iniciado em: $logFile"
    }
    catch {
        Write-Warn "Não foi possível iniciar transcript: $($_.Exception.Message)"
    }
}

function Initialize-Context {
    [CmdletBinding()]
    param()
    Write-Title 'Coleta inicial de contexto'

    $computerSystem = Get-CimInstance Win32_ComputerSystem

    Write-Info "Computador: $($computerSystem.Name)"
    Write-Info "Domínio/Grupo atual: $($computerSystem.Domain)"
    Write-Info "Ingressado em domínio: $($computerSystem.PartOfDomain)"

    if ([string]::IsNullOrWhiteSpace($DomainFqdn)) {
        if ($computerSystem.PartOfDomain -and $computerSystem.Domain -and ($computerSystem.Domain -ne $computerSystem.Name)) {
            $script:DomainFqdn = Read-ValueWithDefault -Question 'Informe o FQDN do domínio AD' -DefaultValue $computerSystem.Domain
        }
        else {
            $script:DomainFqdn = Read-ValueWithDefault -Question 'Informe o FQDN do domínio AD. Exemplo: contoso.local'
        }
    }

    if ([string]::IsNullOrWhiteSpace($DomainNetBIOS)) {
        $defaultNetbios = ($script:DomainFqdn -split '\.')[0].ToUpperInvariant()
        $script:DomainNetBIOS = Read-ValueWithDefault -Question 'Informe o nome NetBIOS do domínio' -DefaultValue $defaultNetbios
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredDc)) {
        Write-Info "DC preferencial informado: $PreferredDc"
    }

    Add-TestResult -Etapa 'Contexto' -Status 'INFO' -Detalhe "Computador=$($computerSystem.Name); DomainFqdn=$DomainFqdn; DomainNetBIOS=$DomainNetBIOS; PartOfDomain=$($computerSystem.PartOfDomain)"
}

function Show-DnsClientConfiguration {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 1 - Configuração DNS do cliente'

    try {
        $dnsConfig = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {
            $_.ServerAddresses -and $_.ServerAddresses.Count -gt 0
        }

        $dnsConfig | Format-Table InterfaceAlias, InterfaceIndex, ServerAddresses -AutoSize

        $allServers = @($dnsConfig | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        Add-TestResult -Etapa 'DNS Cliente' -Status 'INFO' -Detalhe ("DNS configurado: {0}" -f ($allServers -join ', '))

        if ($DnsServers -and $DnsServers.Count -gt 0) {
            $missing = @($DnsServers | Where-Object { $_ -notin $allServers })

            if ($missing.Count -eq 0) {
                Write-Ok 'Os DNS esperados já constam na configuração IPv4.'
                Add-TestResult -Etapa 'DNS Cliente' -Status 'OK' -Detalhe 'DNS esperado encontrado.'
            }
            else {
                Write-Warn "DNS esperado não encontrado: $($missing -join ', ')"
                Add-TestResult -Etapa 'DNS Cliente' -Status 'AVISO' -Detalhe "DNS esperado ausente: $($missing -join ', ')"

                if (Read-YesNo -Question 'Deseja configurar os DNS informados nas interfaces IPv4 ativas agora?' -DefaultYes $false) {
                    $activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
                    foreach ($adapter in $activeAdapters) {
                        try {
                            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DnsServers -ErrorAction Stop
                            Write-Ok "DNS ajustado na interface: $($adapter.Name)"
                            Add-TestResult -Etapa 'Correção DNS Cliente' -Status 'OK' -Detalhe "Interface=$($adapter.Name); DNS=$($DnsServers -join ', ')"
                        }
                        catch {
                            Write-Fail "Falha ao ajustar DNS na interface $($adapter.Name): $($_.Exception.Message)"
                            Add-TestResult -Etapa 'Correção DNS Cliente' -Status 'FALHA' -Detalhe $_.Exception.Message
                        }
                    }
                }
            }
        }
        else {
            Write-Info 'Nenhum DNS esperado foi informado por parâmetro. Apenas exibindo a configuração atual.'
        }
    }
    catch {
        Write-Fail "Falha ao consultar DNS do cliente: $($_.Exception.Message)"
        Add-TestResult -Etapa 'DNS Cliente' -Status 'FALHA' -Detalhe $_.Exception.Message
    }
}

function Test-DnsRecords {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 2 - Resolução DNS e registros SRV do Active Directory'

    $queries = @(
        [PSCustomObject]@{ Name = $DomainFqdn; Type = 'A' },
        [PSCustomObject]@{ Name = "_ldap._tcp.$DomainFqdn"; Type = 'SRV' },
        [PSCustomObject]@{ Name = "_ldap._tcp.dc._msdcs.$DomainFqdn"; Type = 'SRV' },
        [PSCustomObject]@{ Name = "_kerberos._tcp.$DomainFqdn"; Type = 'SRV' },
        [PSCustomObject]@{ Name = "_kerberos._udp.$DomainFqdn"; Type = 'SRV' }
    )

    foreach ($query in $queries) {
        Write-Info "Resolve-DnsName -Type $($query.Type) $($query.Name)"

        try {
            $records = Resolve-DnsName -Name $query.Name -Type $query.Type -ErrorAction Stop
            $records | Format-Table -AutoSize
            Write-Ok "Consulta resolvida: $($query.Name)"
            Add-TestResult -Etapa 'DNS SRV' -Status 'OK' -Detalhe "$($query.Type) $($query.Name) resolvido."
        }
        catch {
            Write-Fail "Falha na consulta DNS: $($query.Name) / $($query.Type) - $($_.Exception.Message)"
            Add-TestResult -Etapa 'DNS SRV' -Status 'FALHA' -Detalhe "$($query.Type) $($query.Name): $($_.Exception.Message)"
        }
    }

    if (Read-YesNo -Question 'Deseja executar ipconfig /flushdns e ipconfig /registerdns?' -DefaultYes $false) {
        ipconfig /flushdns | Out-Host
        ipconfig /registerdns | Out-Host
        Add-TestResult -Etapa 'Correção DNS Cache' -Status 'OK' -Detalhe 'Executado flushdns e registerdns.'
    }
}

function Get-DomainControllerByNltest {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 3 - Descoberta do controlador de domínio'

    $result = Invoke-ExternalCommand -FilePath 'nltest.exe' -ArgumentList @("/dsgetdc:$DomainFqdn", '/force')
    Write-Host $result.Output

    if ($result.ExitCode -eq 0) {
        Write-Ok 'nltest localizou um controlador de domínio.'
        Add-TestResult -Etapa 'Descoberta DC' -Status 'OK' -Detalhe $result.Output
    }
    else {
        Write-Fail 'nltest não conseguiu localizar controlador de domínio.'
        Add-TestResult -Etapa 'Descoberta DC' -Status 'FALHA' -Detalhe $result.Output
    }

    foreach ($line in ($result.Output -split "`r?`n")) {
        if ($line -match '^\s*DC:\s+\\\\(?<dc>\S+)') {
            $script:DetectedDcHost = $Matches.dc.Trim()
        }

        if ($line -match '^\s*(Endere[cç]o|Address):\s+\\\\(?<ip>[0-9a-fA-F\.:]+)') {
            $script:DetectedDcIp = $Matches.ip.Trim()
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredDc)) {
        if (Test-IsIPv4 -Value $PreferredDc) {
            $script:DetectedDcIp = $PreferredDc
        }
        else {
            $script:DetectedDcHost = $PreferredDc
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:DetectedDcHost) -and [string]::IsNullOrWhiteSpace($script:DetectedDcIp)) {
        $manualDc = Read-ValueWithDefault -Question 'Informe manualmente o IP ou FQDN do DC para testar portas'
        if (Test-IsIPv4 -Value $manualDc) {
            $script:DetectedDcIp = $manualDc
        }
        else {
            $script:DetectedDcHost = $manualDc
        }
    }

    Write-Info "DC detectado por nome: $script:DetectedDcHost"
    Write-Info "DC detectado por IP: $script:DetectedDcIp"
}

function Get-DcTarget {
    [CmdletBinding()]
    param()
    if (-not [string]::IsNullOrWhiteSpace($script:DetectedDcIp)) {
        return $script:DetectedDcIp
    }

    if (-not [string]::IsNullOrWhiteSpace($script:DetectedDcHost)) {
        return $script:DetectedDcHost
    }

    return $DomainFqdn
}

function Test-DcPorts {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 4 - Portas essenciais para autenticação no AD'

    $dcTarget = Get-DcTarget
    Write-Info "Alvo dos testes de porta: $dcTarget"

    $ports = @(
        [PSCustomObject]@{ Port = 53;   Service = 'DNS' },
        [PSCustomObject]@{ Port = 88;   Service = 'Kerberos' },
        [PSCustomObject]@{ Port = 135;  Service = 'RPC Endpoint Mapper' },
        [PSCustomObject]@{ Port = 389;  Service = 'LDAP' },
        [PSCustomObject]@{ Port = 445;  Service = 'SMB/CIFS' },
        [PSCustomObject]@{ Port = 464;  Service = 'Kerberos password change' },
        [PSCustomObject]@{ Port = 3268; Service = 'Global Catalog' }
    )

    foreach ($item in $ports) {
        Write-Info "Test-NetConnection $dcTarget -Port $($item.Port) ($($item.Service))"

        try {
            $ok = Test-NetConnection -ComputerName $dcTarget -Port $item.Port -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($ok) {
                Write-Ok "Porta TCP $($item.Port) aberta: $($item.Service)"
                Add-TestResult -Etapa 'Portas AD' -Status 'OK' -Detalhe "TCP $($item.Port) $($item.Service)"
            }
            else {
                Write-Fail "Porta TCP $($item.Port) sem comunicação: $($item.Service)"
                Add-TestResult -Etapa 'Portas AD' -Status 'FALHA' -Detalhe "TCP $($item.Port) $($item.Service) sem comunicação."
            }
        }
        catch {
            Write-Fail "Erro testando porta $($item.Port): $($_.Exception.Message)"
            Add-TestResult -Etapa 'Portas AD' -Status 'FALHA' -Detalhe "TCP $($item.Port): $($_.Exception.Message)"
        }
    }

    Write-Warn 'Observação: Test-NetConnection testa TCP. DNS e Kerberos também podem usar UDP em cenários específicos.'
}

function Test-TimeSync {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 5 - Hora, fuso e sincronização com o domínio'

    $dcForTime = if (-not [string]::IsNullOrWhiteSpace($script:DetectedDcHost)) {
        $script:DetectedDcHost
    }
    else {
        $DomainFqdn
    }

    Write-Info 'Status atual do Windows Time:'
    $timeStatus = Invoke-ExternalCommand -FilePath 'w32tm.exe' -ArgumentList @('/query', '/status')
    Write-Host $timeStatus.Output
    Add-TestResult -Etapa 'Hora' -Status 'INFO' -Detalhe $timeStatus.Output

    Write-Info "Comparação de relógio com: $dcForTime"
    $stripChart = Invoke-ExternalCommand -FilePath 'w32tm.exe' -ArgumentList @('/stripchart', "/computer:$dcForTime", '/samples:5', '/dataonly')
    Write-Host $stripChart.Output

    if ($stripChart.ExitCode -eq 0) {
        Add-TestResult -Etapa 'Hora Stripchart' -Status 'OK' -Detalhe $stripChart.Output
    }
    else {
        Add-TestResult -Etapa 'Hora Stripchart' -Status 'FALHA' -Detalhe $stripChart.Output
    }

    if (Read-YesNo -Question 'Deseja forçar sincronização pela hierarquia do domínio agora?' -DefaultYes $false) {
        Invoke-ExternalCommand -FilePath 'w32tm.exe' -ArgumentList @('/config', '/syncfromflags:domhier', '/update') | ForEach-Object { Write-Host $_.Output }
        Invoke-ExternalCommand -FilePath 'w32tm.exe' -ArgumentList @('/resync', '/rediscover') | ForEach-Object { Write-Host $_.Output }
        Add-TestResult -Etapa 'Correção Hora' -Status 'OK' -Detalhe 'Executado w32tm /config /syncfromflags:domhier /update e /resync /rediscover.'
    }
}

function Test-DomainMembership {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 6 - Ingresso da máquina no domínio'

    try {
        # Mesmo teste usado no atendimento: Get-ComputerInfo | Select-Object CsName,CsDomain,CsPartOfDomain
        $info = Get-ComputerInfo | Select-Object CsName, CsDomain, CsPartOfDomain
    }
    catch {
        Write-Warn "Get-ComputerInfo falhou ou não está disponível. Usando Win32_ComputerSystem como fallback: $($_.Exception.Message)"
        $computerSystem = Get-CimInstance Win32_ComputerSystem
        $info = [PSCustomObject]@{
            CsName         = $computerSystem.Name
            CsDomain       = $computerSystem.Domain
            CsPartOfDomain = $computerSystem.PartOfDomain
        }
    }

    $info | Format-List
    Add-TestResult -Etapa 'Ingresso no domínio' -Status 'INFO' -Detalhe "Name=$($info.CsName); Domain=$($info.CsDomain); PartOfDomain=$($info.CsPartOfDomain)"

    if (-not [bool]$info.CsPartOfDomain) {
        Write-Fail 'A máquina não está ingressada em domínio.'
        Add-TestResult -Etapa 'Ingresso no domínio' -Status 'FALHA' -Detalhe 'PartOfDomain=False'

        if (Read-YesNo -Question "Deseja ingressar esta máquina no domínio $DomainFqdn agora?" -DefaultYes $false) {
            $cred = Get-DomainCredentialSafe -Purpose "ingressar máquina no domínio $DomainFqdn"

            try {
                Add-Computer -DomainName $DomainFqdn -Credential $cred -Force -Verbose -ErrorAction Stop
                Write-Ok 'Ingresso no domínio solicitado com sucesso.'
                Add-TestResult -Etapa 'Correção Ingresso' -Status 'OK' -Detalhe "Add-Computer -DomainName $DomainFqdn executado."

                if (Read-YesNo -Question 'É necessário reiniciar para concluir. Deseja reiniciar agora?' -DefaultYes $true) {
                    Restart-Computer -Force
                }
            }
            catch {
                Write-Fail "Falha ao ingressar no domínio: $($_.Exception.Message)"
                Add-TestResult -Etapa 'Correção Ingresso' -Status 'FALHA' -Detalhe $_.Exception.Message
            }
        }

        return $false
    }

    if ($info.CsDomain -ieq $DomainFqdn) {
        Write-Ok "Máquina ingressada no domínio esperado: $DomainFqdn"
        Add-TestResult -Etapa 'Ingresso no domínio' -Status 'OK' -Detalhe "Domain=$($info.CsDomain)"
    }
    else {
        Write-Warn "Máquina ingressada em domínio diferente do informado. Atual=$($info.CsDomain); Esperado=$DomainFqdn"
        Add-TestResult -Etapa 'Ingresso no domínio' -Status 'AVISO' -Detalhe "Atual=$($info.CsDomain); Esperado=$DomainFqdn"
    }

    return $true
}

function Test-NltestSecureChannel {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 7 - nltest /sc_query e /sc_verify'

    $query = Invoke-ExternalCommand -FilePath 'nltest.exe' -ArgumentList @("/sc_query:$DomainFqdn")
    Write-Host $query.Output

    if ($query.ExitCode -eq 0 -and $query.Output -match 'NERR_Success|0x0') {
        Write-Ok 'nltest /sc_query retornou sucesso.'
        Add-TestResult -Etapa 'nltest sc_query' -Status 'OK' -Detalhe $query.Output
    }
    else {
        Write-Fail 'nltest /sc_query não retornou sucesso.'
        Add-TestResult -Etapa 'nltest sc_query' -Status 'FALHA' -Detalhe $query.Output
    }

    $verify = Invoke-ExternalCommand -FilePath 'nltest.exe' -ArgumentList @("/sc_verify:$DomainFqdn")
    Write-Host $verify.Output

    if ($verify.ExitCode -eq 0 -and $verify.Output -match 'NERR_Success|0x0') {
        Write-Ok 'nltest /sc_verify retornou sucesso.'
        Add-TestResult -Etapa 'nltest sc_verify' -Status 'OK' -Detalhe $verify.Output
    }
    else {
        Write-Fail 'nltest /sc_verify não retornou sucesso.'
        Add-TestResult -Etapa 'nltest sc_verify' -Status 'FALHA' -Detalhe $verify.Output
    }
}

function Test-MachineKerberosTickets {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 8 - Tickets Kerberos da conta de máquina'

    $machinePrincipal = "$($env:COMPUTERNAME)`$"
    $result = Invoke-ExternalCommand -FilePath 'klist.exe' -ArgumentList @('-li', '0x3e7')
    Write-Host $result.Output

    if ($result.ExitCode -eq 0 -and $result.Output -match ([regex]::Escape($machinePrincipal))) {
        Write-Ok "Foram encontrados tickets Kerberos da conta de máquina: $machinePrincipal"
        Add-TestResult -Etapa 'klist máquina' -Status 'OK' -Detalhe "Principal esperado encontrado: $machinePrincipal"
    }
    elseif ($result.ExitCode -eq 0 -and $result.Output -match 'Tíquetes em Cache:\s*\(0\)|Cached Tickets:\s*\(0\)') {
        Write-Warn 'Cache Kerberos da conta de máquina está vazio. Isso pode ocorrer antes de reparar/reiniciar ou quando o canal seguro está quebrado.'
        Add-TestResult -Etapa 'klist máquina' -Status 'AVISO' -Detalhe 'Cache da conta de máquina vazio.'
    }
    else {
        Write-Warn "Não encontrei claramente o principal $machinePrincipal no cache da conta de máquina. Revise a saída acima."
        Add-TestResult -Etapa 'klist máquina' -Status 'AVISO' -Detalhe $result.Output
    }
}

function Test-AndRepairComputerSecureChannel {
    [CmdletBinding()]
    param()
    Write-Title 'Teste 9 - Test-ComputerSecureChannel'

    $secureChannelOk = $false

    try {
        $secureChannelOk = Test-ComputerSecureChannel -Verbose -ErrorAction Continue
    }
    catch {
        Write-Fail "Erro ao executar Test-ComputerSecureChannel: $($_.Exception.Message)"
        Add-TestResult -Etapa 'Secure Channel' -Status 'FALHA' -Detalhe $_.Exception.Message
        $secureChannelOk = $false
    }

    if ($secureChannelOk) {
        Write-Ok 'O canal seguro entre a máquina e o domínio está íntegro.'
        Add-TestResult -Etapa 'Secure Channel' -Status 'OK' -Detalhe 'Test-ComputerSecureChannel=True'
        return $true
    }

    Write-Fail 'O canal seguro entre a máquina e o domínio está quebrado.'
    Add-TestResult -Etapa 'Secure Channel' -Status 'FALHA' -Detalhe 'Test-ComputerSecureChannel=False'

    if (-not (Read-YesNo -Question 'Deseja tentar reparar o canal seguro agora com credencial de domínio?' -DefaultYes $true)) {
        return $false
    }

    $cred = Get-DomainCredentialSafe -Purpose 'reparar canal seguro da conta de máquina'
    $repairOk = $false

    try {
        $repairOk = Test-ComputerSecureChannel -Repair -Credential $cred -Verbose -ErrorAction Stop
    }
    catch {
        Write-Fail "Falha no Test-ComputerSecureChannel -Repair: $($_.Exception.Message)"
        Add-TestResult -Etapa 'Reparo Secure Channel' -Status 'FALHA' -Detalhe $_.Exception.Message
        $repairOk = $false
    }

    if (-not $repairOk) {
        Write-Warn 'A primeira tentativa de reparo não confirmou sucesso.'

        if (Read-YesNo -Question 'Deseja tentar Reset-ComputerMachinePassword apontando diretamente para o DC?' -DefaultYes $true) {
            $server = if (-not [string]::IsNullOrWhiteSpace($script:DetectedDcHost)) {
                $script:DetectedDcHost
            }
            elseif (-not [string]::IsNullOrWhiteSpace($script:DetectedDcIp)) {
                $script:DetectedDcIp
            }
            else {
                $DomainFqdn
            }

            try {
                Reset-ComputerMachinePassword -Server $server -Credential $cred -ErrorAction Stop
                $repairOk = Test-ComputerSecureChannel -Verbose -ErrorAction Continue

                if ($repairOk) {
                    Write-Ok 'Reset-ComputerMachinePassword reparou o canal seguro.'
                    Add-TestResult -Etapa 'Reset senha máquina' -Status 'OK' -Detalhe "Server=$server"
                }
                else {
                    Write-Fail 'Mesmo após Reset-ComputerMachinePassword, o canal seguro ainda não validou.'
                    Add-TestResult -Etapa 'Reset senha máquina' -Status 'FALHA' -Detalhe "Server=$server; Test-ComputerSecureChannel=False"
                }
            }
            catch {
                Write-Fail "Falha no Reset-ComputerMachinePassword: $($_.Exception.Message)"
                Add-TestResult -Etapa 'Reset senha máquina' -Status 'FALHA' -Detalhe $_.Exception.Message
            }
        }
    }

    if ($repairOk) {
        Write-Ok 'Canal seguro reparado com sucesso.'
        Add-TestResult -Etapa 'Reparo Secure Channel' -Status 'OK' -Detalhe 'Reparo concluído.'

        if (Read-YesNo -Question 'Deseja limpar cache DNS e registrar DNS da máquina agora?' -DefaultYes $true) {
            ipconfig /flushdns | Out-Host
            ipconfig /registerdns | Out-Host
            Add-TestResult -Etapa 'Pós-reparo DNS' -Status 'OK' -Detalhe 'Executado flushdns/registerdns.'
        }

        if (Read-YesNo -Question 'Deseja apagar tickets Kerberos da conta de máquina para forçar renovação?' -DefaultYes $false) {
            Invoke-ExternalCommand -FilePath 'klist.exe' -ArgumentList @('purge', '-li', '0x3e7') | ForEach-Object { Write-Host $_.Output }
            Add-TestResult -Etapa 'Pós-reparo Kerberos' -Status 'OK' -Detalhe 'Executado klist purge -li 0x3e7.'
        }

        Write-Info 'Executando validações pós-reparo.'
        Test-NltestSecureChannel
        Test-MachineKerberosTickets

        if (Read-YesNo -Question 'Recomenda-se reiniciar para validar o logon da conta de máquina. Deseja reiniciar agora?' -DefaultYes $true) {
            Restart-Computer -Force
        }

        return $true
    }

    Write-Fail 'Não foi possível reparar automaticamente o canal seguro.'
    Write-Warn 'Próximo passo recomendado: resetar a conta de computador no AD e, se necessário, remover e reinserir a máquina no domínio.'

    if (Read-YesNo -Question 'A conta de computador já foi resetada no AD/RSAT/Samba? Deseja tentar reparar novamente?' -DefaultYes $false) {
        return (Test-AndRepairComputerSecureChannel)
    }

    if (Read-YesNo -Question 'Deseja remover esta máquina do domínio para WORKGROUP agora? Será necessário reiniciar e ingressar novamente depois.' -DefaultYes $false) {
        Invoke-DomainRemoval
    }

    return $false
}

function Invoke-DomainRemoval {
    [CmdletBinding()]
    param()
    Write-Title 'Etapa opcional - Remoção do domínio'

    $cred = Get-DomainCredentialSafe -Purpose 'remover máquina do domínio'
    $workgroup = Read-ValueWithDefault -Question 'Nome do grupo de trabalho temporário' -DefaultValue 'WORKGROUP'

    try {
        Remove-Computer -UnjoinDomainCredential $cred -WorkgroupName $workgroup -Force -PassThru -Verbose -ErrorAction Stop
        Write-Ok "Máquina removida do domínio para o grupo $workgroup."
        Add-TestResult -Etapa 'Remoção domínio' -Status 'OK' -Detalhe "Workgroup=$workgroup"
        Write-Warn 'Após reiniciar, execute este script novamente para ingressar a máquina no domínio.'

        if (Read-YesNo -Question 'Deseja reiniciar agora?' -DefaultYes $true) {
            Restart-Computer -Force
        }
    }
    catch {
        Write-Fail "Falha ao remover do domínio: $($_.Exception.Message)"
        Add-TestResult -Etapa 'Remoção domínio' -Status 'FALHA' -Detalhe $_.Exception.Message
        Write-Warn 'Se a confiança estiver muito quebrada, use uma conta local administrativa, remova manualmente do domínio, reinicie e ingresse novamente.'
    }
}

function Show-FinalSummary {
    [CmdletBinding()]
    param()
    Write-Title 'Resumo final dos testes'

    $script:Results | Format-Table DataHora, Etapa, Status, Detalhe -AutoSize -Wrap

    $failed = @($script:Results | Where-Object { $_.Status -eq 'FALHA' })
    $warnings = @($script:Results | Where-Object { $_.Status -eq 'AVISO' })

    Write-Host ''
    if ($failed.Count -eq 0) {
        Write-Ok 'Nenhuma falha crítica ficou registrada no resumo.'
    }
    else {
        Write-Fail "Falhas registradas: $($failed.Count)"
    }

    if ($warnings.Count -gt 0) {
        Write-Warn "Avisos registrados: $($warnings.Count)"
    }

    Write-Host ''
    Write-Info 'Critério de sucesso esperado:'
    Write-Info '1. Resolve-DnsName do domínio e SRV retornando o DC correto.'
    Write-Info '2. nltest /dsgetdc localizando o DC correto.'
    Write-Info '3. Portas 53, 88, 135, 389, 445, 464 e 3268 comunicando com o DC.'
    Write-Info '4. Test-ComputerSecureChannel retornando True.'
    Write-Info '5. nltest /sc_query e /sc_verify retornando Status = 0 / NERR_Success.'
    Write-Info "6. klist -li 0x3e7 exibindo tickets para $($env:COMPUTERNAME)`$@$($DomainFqdn.ToUpperInvariant())."
}

try {
    Initialize-Log

    Write-Title 'Diagnóstico e reparo de conta de máquina no Active Directory'
    Write-Info 'Execute este script em PowerShell como Administrador na estação Windows afetada.'
    Write-Info 'Nenhuma correção crítica será aplicada sem confirmação.'

    Initialize-Context
    Show-DnsClientConfiguration
    Test-DnsRecords
    Get-DomainControllerByNltest
    Test-DcPorts
    Test-TimeSync

    $joined = Test-DomainMembership
    if ($joined) {
        Test-NltestSecureChannel
        Test-MachineKerberosTickets
        Test-AndRepairComputerSecureChannel | Out-Null
    }

    Show-FinalSummary
}
finally {
    try {
        if (-not $NoTranscript) {
            Stop-Transcript | Out-Null
        }
    }
    catch {
        # Ignora encerramento de transcript quando ele não estiver ativo.
    }
}
