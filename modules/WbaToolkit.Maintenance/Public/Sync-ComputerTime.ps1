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
    [CmdletBinding()]
    param(
        [switch]$Apply,

        [ValidateSet('pool.ntp.br', 'time.windows.com')]
        [string]$NtpServer = 'pool.ntp.br',

        [string]$TimeZoneId
    )

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

    $sourceResult = & w32tm.exe /query /source 2>&1
    $sourceExit = $LASTEXITCODE
    $sourceBefore = (($sourceResult | ForEach-Object { [string]$_ }) -join ' ').Trim()
    if ($sourceExit -ne 0) { $errors.Add("w32tm /query /source retornou ${sourceExit}: $sourceBefore") }

    $statusResult = & w32tm.exe /query /status 2>&1
    $statusExit = $LASTEXITCODE
    $statusBefore = (($statusResult | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ($statusExit -ne 0) { $errors.Add("w32tm /query /status retornou $statusExit") }

    $sourceMode = if ($partOfDomain) { 'domhier' } else { 'manual' }
    if ($Apply) {
        try {
            if ($partOfDomain) {
                & w32tm.exe /config /syncfromflags:domhier /update 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "w32tm domhier retornou $LASTEXITCODE" }
                $actions.Add('Fonte configurada como hierarquia do domínio (domhier)')
            }
            else {
                $peerList = "$NtpServer,0x8"
                & w32tm.exe /config "/manualpeerlist:$peerList" /syncfromflags:manual /update 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "w32tm NTP externo retornou $LASTEXITCODE" }
                $actions.Add("Fonte configurada como $NtpServer")
            }

            if ($service -and $service.Status -ne 'Running') {
                Set-Service -Name W32Time -StartupType Automatic -ErrorAction Stop
                Start-Service -Name W32Time -ErrorAction Stop
                $actions.Add('Serviço W32Time iniciado')
            }

            & w32tm.exe /resync /force 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "w32tm /resync retornou $LASTEXITCODE" }
            $actions.Add('Sincronização solicitada')

            if (-not [string]::IsNullOrWhiteSpace($TimeZoneId)) {
                $validZone = Get-TimeZone -ListAvailable -ErrorAction Stop |
                    Where-Object { $_.Id -eq $TimeZoneId } | Select-Object -First 1
                if (-not $validZone) { throw "Fuso horário não reconhecido: $TimeZoneId" }
                if (-not $timezoneBefore -or $timezoneBefore.Id -ne $TimeZoneId) {
                    Set-TimeZone -Id $TimeZoneId -ErrorAction Stop
                    $actions.Add("Fuso horário aplicado: $TimeZoneId")
                }
                else { $actions.Add("Fuso horário já estava correto: $TimeZoneId") }
            }
        }
        catch { $errors.Add($_.Exception.Message) }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TimeZoneId)) {
        $actions.Add('Fuso informado apenas para referência; use -Apply para alterar')
    }

    $timezoneAfter = $timezoneBefore
    try { $timezoneAfter = Get-TimeZone -ErrorAction Stop } catch { }
    $postSource = & w32tm.exe /query /source 2>&1
    $postSourceExit = $LASTEXITCODE
    $sourceAfter = (($postSource | ForEach-Object { [string]$_ }) -join ' ').Trim()
    if ($postSourceExit -ne 0 -and $Apply) { $errors.Add("Não foi possível confirmar a fonte final: código $postSourceExit") }

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
