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

    $points | ForEach-Object {
        $creationTime = $null
        try {
            $creationTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)
        } catch {
            $creationTime = $_.CreationTime
        }

        [pscustomobject]@{
            SequenceNumber = $_.SequenceNumber
            Description    = $_.Description
            CreationTime   = $creationTime
            RestorePointType = $_.RestorePointType
            EventType      = $_.EventType
        }
    }
}
