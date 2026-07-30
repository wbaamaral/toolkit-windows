function Get-WindowsServiceDetail {
    <#
    .SYNOPSIS
        Exibe detalhes completos de um servico Windows.

    .DESCRIPTION
        Coleta informacoes detalhadas: status, tipo de inicializacao, conta de logon,
        dependencias, descricao, caminho do executavel, PID e tempo de atividade.

    .PARAMETER Name
        Nome do servico (obrigatorio).

    .OUTPUTS
        PSCustomObject com: Name, DisplayName, Status, StartType, Account, Path,
        ProcessId, Description, DependentServices, RequiredServices.

    .EXAMPLE
        Get-WindowsServiceDetail -Name 'W32Time'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $resolved = Resolve-WindowsService -Name $Name
    if (-not $resolved.Exists) {
        return [pscustomobject]@{
            Success = $false
            Message = $resolved.Message
        }
    }

    $svc = $resolved.Service

    $wmi = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue

    $dependentNames = @()
    try { $dependentNames = @($svc.DependentServices | ForEach-Object { $_.Name }) } catch { }

    $requiredNames = @()
    try { $requiredNames = @($svc.RequiredServices | ForEach-Object { $_.Name }) } catch { }

    [pscustomobject]@{
        Success           = $true
        Name              = $svc.Name
        DisplayName       = $svc.DisplayName
        Status            = $svc.Status.ToString()
        StartType         = if ($wmi) { switch ($wmi.StartMode) { 'Auto' { 'Automatic' } default { $wmi.StartMode } } } else { 'Unknown' }
        Account           = if ($wmi) { $wmi.StartName } else { 'Unknown' }
        Path              = if ($wmi) { $wmi.PathName } else { '' }
        ProcessId         = if ($wmi) { $wmi.ProcessId } else { 0 }
        Description       = if ($wmi) { $wmi.Description } else { '' }
        DependentServices = $dependentNames
        RequiredServices  = $requiredNames
        DependentCount    = $dependentNames.Count
        RequiredCount     = $requiredNames.Count
    }
}