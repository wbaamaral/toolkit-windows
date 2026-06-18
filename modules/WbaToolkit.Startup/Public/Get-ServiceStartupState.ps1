function Get-ServiceStartupState {
    <#
    .SYNOPSIS
        Retorna o estado e o tipo de inicializacao de servicos do Windows.

    .DESCRIPTION
        Consulta os servicos informados pelo nome e retorna um objeto com o estado
        atual e o tipo de inicializacao (Auto, Manual, Disabled) de cada um.
        Servicos nao encontrados sao incluidos no resultado com Status 'Nao encontrado'.

    .PARAMETER ServiceName
        Um ou mais nomes de servico a consultar. Aceita lista ou item unico.
        Padrao: conjunto de servicos com impacto conhecido em uso de disco elevado.

    .EXAMPLE
        Get-ServiceStartupState

        Retorna o estado dos servicos padrao monitorados pelo toolkit.

    .EXAMPLE
        Get-ServiceStartupState -ServiceName 'WSearch', 'SysMain'

        Retorna o estado de WSearch e SysMain.

    .EXAMPLE
        Get-ServiceStartupState -ServiceName 'Spooler'

        Retorna o estado do servico de spooler de impressao.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array de objetos com as propriedades: Name, DisplayName, Status, StartType.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ServiceName = @('WSearch', 'SysMain', 'DPS', 'BITS', 'Ndu', 'WinDefend', 'DiagTrack', 'OneSyncSvc')
    )

    $services = foreach ($name in @($ServiceName)) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            $cim = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
            [pscustomobject]@{
                Name        = $name
                DisplayName = $svc.DisplayName
                Status      = [string]$svc.Status
                StartType   = if ($cim) { $cim.StartMode } else { $null }
            }
        }
        else {
            [pscustomobject]@{
                Name        = $name
                DisplayName = $null
                Status      = 'Nao encontrado'
                StartType   = $null
            }
        }
    }

    return @($services)
}
