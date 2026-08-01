function Get-WindowsServiceStatus {
    <#
    .SYNOPSIS
        Lista servicos Windows com filtros por nome, status e tipo de inicializacao.

    .DESCRIPTION
        Retorna objetos com Name, DisplayName, Status, StartType e Path para cada
        servico que atende aos filtros especificados.

    .PARAMETER Name
        Nome ou padrao (wildcard) do servico. Ex.: 'W32Time', 'Win*'.

    .PARAMETER Status
        Filtrar por status: Running, Stopped, Paused.

    .PARAMETER StartType
        Filtrar por tipo de inicializacao: Automatic, Manual, Disabled.

    .PARAMETER DisplayName
        Nome de exibicao (wildcard). Ex.: '*Time*'.

    .OUTPUTS
        PSCustomObject[] com: Name, DisplayName, Status, StartType, Path.

    .EXAMPLE
        Get-WindowsServiceStatus -Status Running

    .EXAMPLE
        Get-WindowsServiceStatus -Name 'Win*' -StartType Automatic
    #>
    [CmdletBinding()]
    param(
        [string]$Name = '*',

        [ValidateSet('Running', 'Stopped', 'Paused', 'StartPending', 'StopPending')]
        [string]$Status,

        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartType,

        [string]$DisplayName = '*'
    )

    $services = @(Get-Service -Name $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like $DisplayName })

    if ($Status) {
        $services = @($services | Where-Object { $_.Status.ToString() -eq $Status })
    }

    $wmiMap = @{}
    try {
        $wmiAll = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue
        foreach ($w in $wmiAll) {
            $wmiMap[$w.Name] = $w
        }
    } catch { Write-Verbose "Nao foi possivel consultar Win32_Service: $($_.Exception.Message)" }

    $results = foreach ($svc in $services) {
        $wmi = $wmiMap[$svc.Name]

        $rawStartType = if ($wmi) { $wmi.StartMode } else { 'Unknown' }
        $resolvedStartType = switch ($rawStartType) {
            'Auto'     { 'Automatic' }
            'Manual'   { 'Manual' }
            'Disabled' { 'Disabled' }
            'Boot'     { 'Boot' }
            'System'   { 'System' }
            default    { $rawStartType }
        }

        $path = if ($wmi) { $wmi.PathName } else { '' }

        [pscustomobject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            Status      = $svc.Status.ToString()
            StartType   = $resolvedStartType
            Path        = $path
        }
    }

    if ($StartType) {
        $results = @($results | Where-Object { $_.StartType -eq $StartType })
    }

    @($results)
}
