function Sync-ComputerTime {
    <#
    .SYNOPSIS
        Diagnostica ou corrige a fonte de tempo e o fuso horário do Windows.

    .DESCRIPTION
        Clientes ingressados no Active Directory usam a hierarquia do domínio.
        Clientes fora do domínio usam uma fonte NTP externa. A execução padrão
        é somente leitura; -Apply autoriza a alteração da configuração.

    .PARAMETER Apply
        Aplica a fonte de tempo e, quando informado, o fuso horário.

    .PARAMETER NtpServer
        Fonte NTP externa para clientes fora do domínio. Padrão: pool.ntp.br.

    .PARAMETER TimeZoneId
        ID do fuso horário Windows a aplicar durante -Apply. Sem este parâmetro,
        o fuso atual apenas é verificado.

    .OUTPUTS
        Objeto com contexto da máquina, fonte, serviço, fuso, ações e erros.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Apply,

        [ValidateSet('pool.ntp.br', 'time.windows.com')]
        [string]$NtpServer = 'pool.ntp.br',

        [string]$TimeZoneId
    )

    # Mock para lab Docker/Linux (WBA_MOCK_AD) — simula sucesso sem w32tm real
    if (Test-ToolkitLabMock) {
        $computerMock = try { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue } catch { $null }
        $tzMock = try { Get-TimeZone -ErrorAction SilentlyContinue } catch { $null }
        $mockSource = '172.20.0.10 (mock WBA_MOCK_AD)'
        $actionsMock = New-Object 'System.Collections.Generic.List[string]'
        if ($Apply) { $actionsMock.Add('Fonte configurada (mock WBA_MOCK_AD)') ; $actionsMock.Add('Sincronização solicitada (mock)') }
        return [pscustomobject]@{
            ComputerName   = if ($computerMock) { [string]$computerMock.Name } else { $env:COMPUTERNAME }
            PartOfDomain   = $true
            Domain         = 'wba.test'
            SourceMode     = 'domhier'
            NtpServer      = $null
            SourceBefore   = $mockSource
            SourceAfter    = $mockSource
            ServiceStatus  = 'Running'
            TimeZoneBefore = if ($tzMock) { [string]$tzMock.Id } else { 'E. South America Standard Time' }
            TimeZoneAfter  = if ($tzMock) { [string]$tzMock.Id } else { 'E. South America Standard Time' }
            ApplyRequested = [bool]$Apply
            Actions        = @($actionsMock)
            Errors         = @()
            Success        = $true
            GeneratedAt    = Get-Date
        }
    }

    $actions = New-Object 'System.Collections.Generic.List[string]'
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $computer = $null
    $service = $null
    $timezoneBefore = $null
    $sourceBefore = ''
    $statusBefore = ''

    try { $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop }
    catch { $errors.Add("Não foi possível consultar o computador: $($_.Exception.Message)") }

    try { $service = Get-Service -Name W32Time -ErrorAction Stop }
    catch { $errors.Add("Não foi possível consultar o serviço W32Time: $($_.Exception.Message)") }

    try { $timezoneBefore = Get-TimeZone -ErrorAction Stop }
    catch { $errors.Add("Não foi possível consultar o fuso horário: $($_.Exception.Message)") }

    $partOfDomain = if ($computer) { [bool]$computer.PartOfDomain } else { $false }
    $domain = if ($computer) { [string]$computer.Domain } else { '' }

    $sourceQuery = Invoke-W32tm -ArgumentList @('/query', '/source')
    $sourceBefore = $sourceQuery.Output -replace '\s+', ' '
    if ($sourceQuery.ExitCode -ne 0) { $errors.Add("w32tm /query /source retornou $($sourceQuery.ExitCode): $sourceBefore") }

    $statusQuery = Invoke-W32tm -ArgumentList @('/query', '/status')
    if ($statusQuery.ExitCode -ne 0) { $errors.Add("w32tm /query /status retornou $($statusQuery.ExitCode)") }

    $sourceMode = if ($partOfDomain) { 'domhier' } else { 'manual' }
    $applyAuthorized = $Apply -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Configurar fonte de tempo e fuso horario')
    if ($applyAuthorized) {
        # Fonte de tempo: o servico precisa estar em execucao antes do 'w32tm /config /update',
        # senao o comando falha (0x80070426) e nada e aplicado.
        try {
            if ($service -and $service.Status -ne 'Running') {
                Set-Service -Name W32Time -StartupType Automatic -ErrorAction Stop
                Start-Service -Name W32Time -ErrorAction Stop
                $actions.Add('Serviço W32Time iniciado')
            }

            if ($partOfDomain) {
                $config = Invoke-W32tm -ArgumentList @('/config', '/syncfromflags:domhier', '/update')
                if ($config.ExitCode -ne 0) { throw "w32tm domhier retornou $($config.ExitCode): $($config.Output)" }
                $actions.Add('Fonte configurada como hierarquia do domínio (domhier)')
            }
            else {
                $config = Invoke-W32tm -ArgumentList @('/config', "/manualpeerlist:$NtpServer,0x8", '/syncfromflags:manual', '/update')
                if ($config.ExitCode -ne 0) { throw "w32tm NTP externo retornou $($config.ExitCode): $($config.Output)" }
                $actions.Add("Fonte configurada como $NtpServer")
            }

            $resync = Invoke-W32tm -ArgumentList @('/resync', '/force')
            if ($resync.ExitCode -ne 0) { throw "w32tm /resync retornou $($resync.ExitCode): $($resync.Output)" }
            $actions.Add('Sincronização solicitada')
        }
        catch { $errors.Add($_.Exception.Message) }

        # Fuso horario: independente da fonte de tempo (ADR 0031); falha na sincronizacao
        # nao impede aplicar o fuso pedido, e vice-versa.
        if (-not [string]::IsNullOrWhiteSpace($TimeZoneId)) {
            try {
                $validZone = Get-TimeZone -ListAvailable -ErrorAction Stop |
                    Where-Object { $_.Id -eq $TimeZoneId } | Select-Object -First 1
                if (-not $validZone) { throw "Fuso horário não reconhecido: $TimeZoneId" }
                if (-not $timezoneBefore -or $timezoneBefore.Id -ne $TimeZoneId) {
                    Set-TimeZone -Id $TimeZoneId -ErrorAction Stop
                    $actions.Add("Fuso horário aplicado: $TimeZoneId")
                }
                else { $actions.Add("Fuso horário já estava correto: $TimeZoneId") }
            }
            catch { $errors.Add($_.Exception.Message) }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TimeZoneId)) {
        $actions.Add('Fuso informado apenas para referência; use -Apply para alterar')
    }

    $timezoneAfter = $timezoneBefore
    try { $timezoneAfter = Get-TimeZone -ErrorAction Stop }
    catch { Write-Verbose "Nao foi possivel confirmar o fuso horario final: $($_.Exception.Message)" }
    $postSourceQuery = Invoke-W32tm -ArgumentList @('/query', '/source')
    $sourceAfter = $postSourceQuery.Output -replace '\s+', ' '
    if ($applyAuthorized) {
        # ADR 0031: a fonte aplicada e confirmada por 'w32tm /query /source'.
        if ($postSourceQuery.ExitCode -ne 0) {
            $errors.Add("Não foi possível confirmar a fonte final: código $($postSourceQuery.ExitCode)")
        }
        elseif ($sourceAfter -match 'Local CMOS Clock|Free-running System Clock') {
            $errors.Add("Fonte final ainda é o relógio local: $sourceAfter")
        }
        elseif (-not $partOfDomain -and $sourceAfter -notlike "*$NtpServer*") {
            $errors.Add("Fonte final '$sourceAfter' difere da configurada ($NtpServer).")
        }
    }

    [pscustomobject]@{
        ComputerName    = if ($computer) { [string]$computer.Name } else { $env:COMPUTERNAME }
        PartOfDomain    = $partOfDomain
        Domain          = $domain
        SourceMode      = $sourceMode
        NtpServer       = if ($partOfDomain) { $null } else { $NtpServer }
        SourceBefore    = $sourceBefore
        SourceAfter     = $sourceAfter
        ServiceStatus   = if ($service) { [string]$service.Status } else { 'Desconhecido' }
        TimeZoneBefore  = if ($timezoneBefore) { [string]$timezoneBefore.Id } else { '' }
        TimeZoneAfter    = if ($timezoneAfter) { [string]$timezoneAfter.Id } else { '' }
        ApplyRequested  = [bool]$Apply
        Actions         = @($actions)
        Errors          = @($errors)
        Success         = ($errors.Count -eq 0)
        GeneratedAt     = Get-Date
    }
}
