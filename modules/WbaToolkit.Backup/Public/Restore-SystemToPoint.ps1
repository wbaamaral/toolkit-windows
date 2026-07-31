function Restore-SystemToPoint {
    <#
    .SYNOPSIS
        Restaura o sistema para um ponto de restauracao.
    .DESCRIPTION
        Restaura o Windows para o estado de um restore point especifico.
        REQUER reinicializacao. O sistema sera restaurado na proxima boot.
    .PARAMETER SequenceNumber
        Numero de sequencia do restore point.
    .NOTES
        PERIGO: Isso revertera mudancas de sistema. Confirme antes de executar.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [int]$SequenceNumber
    )

    $point = Get-ComputerRestorePoint -RestorePoint $SequenceNumber -ErrorAction SilentlyContinue
    if (-not $point) { throw "Restore point #$SequenceNumber nao encontrado." }

    if ($PSCmdlet.ShouldProcess("Restore point #$SequenceNumber ($($point.Description))", 'Restaurar sistema')) {
        try {
            Restore-Computer -RestorePoint $SequenceNumber -ErrorAction Stop
            Write-Warning "Sistema sera restaurado na proxima reinicializacao."
        } catch {
            Write-Error "Falha ao agendar restauracao: $_"
        }
    }
}
