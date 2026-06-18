function Get-CimInstanceSafe {
    <#
    .SYNOPSIS
        Consulta instancias CIM com tratamento de erro seguro.

    .DESCRIPTION
        Encapsula Get-CimInstance com try/catch e retorna array vazio em caso
        de falha, em vez de propagar excecao. Erros sao emitidos via
        Write-Verbose para nao interromper o fluxo do script chamador.

    .PARAMETER ClassName
        Nome da classe CIM a consultar (ex.: Win32_VideoController).

    .PARAMETER Namespace
        Namespace CIM. Padrao: root/cimv2.

    .PARAMETER Filter
        Filtro WQL opcional (ex.: "Name='WSearch'"). Quando omitido, retorna
        todas as instancias da classe.

    .EXAMPLE
        $gpus = Get-CimInstanceSafe -ClassName 'Win32_VideoController'

        Retorna todas as controladoras de video ou array vazio se falhar.

    .EXAMPLE
        $svc = Get-CimInstanceSafe -ClassName 'Win32_Service' -Filter "Name='WSearch'"

        Retorna o servico WSearch ou array vazio em caso de erro.

    .EXAMPLE
        $monitors = Get-CimInstanceSafe -Namespace 'root/wmi' -ClassName 'WmiMonitorID'

        Consulta monitores em namespace alternativo.

    .OUTPUTS
        System.Object[]
        Array com as instancias retornadas ou array vazio em caso de erro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,

        [Parameter(Mandatory = $false)]
        [string]$Namespace = 'root/cimv2',

        [Parameter(Mandatory = $false)]
        [string]$Filter
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Filter)) {
            return @(Get-CimInstance -ClassName $ClassName -Namespace $Namespace -ErrorAction Stop)
        }
        return @(Get-CimInstance -ClassName $ClassName -Namespace $Namespace -Filter $Filter -ErrorAction Stop)
    }
    catch {
        Write-Verbose "Get-CimInstanceSafe: falha ao consultar $Namespace/$ClassName. $($_.Exception.Message)"
        return @()
    }
}
