function Get-RestorePointInfo {
    <#
    .SYNOPSIS
        Lista pontos de restauracao do sistema.
    .DESCRIPTION
        Retorna detalhes dos restore points existentes com data, descricao e tipo.
    .PARAMETER LastN
        Retorna apenas os N mais recentes.
    .OUTPUTS
        Lista de PSCustomObject.
    #>
    [CmdletBinding()]
    param(
        [int]$LastN
    )

    try {
        $points = Get-ComputerRestorePoint -ErrorAction Stop
    } catch {
        Write-Warning "Nao foi possivel listar restore points: $_"
        return @()
    }

    if ($LastN -gt 0) {
        $points = $points | Select-Object -Last $LastN
    }

    foreach ($point in $points) {
        # Dentro do catch, $_ e o erro, nao o ponto: usar a variavel do laco.
        $creationTime = $null
        try {
            $creationTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($point.CreationTime)
        } catch {
            $creationTime = $point.CreationTime
        }

        [pscustomobject]@{
            SequenceNumber = $point.SequenceNumber
            Description    = $point.Description
            CreationTime   = $creationTime
            RestorePointType = $point.RestorePointType
            EventType      = $point.EventType
        }
    }
}
