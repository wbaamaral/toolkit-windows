function Remove-RestorePoint {
    <#
    .SYNOPSIS
        Remove pontos de restauracao.
    .DESCRIPTION
        Remove restore points por idade, quantidade ou sequencia especifica.
        Usa a API SRRemoveRestorePoint (srclient.dll) para remover cada ponto pelo
        SequenceNumber e reporta quantos foram de fato removidos.
    .PARAMETER OlderThanDays
        Remove restore points mais antigos que N dias.
    .PARAMETER KeepLast
        Mantem apenas os N mais recentes, removendo o resto.
    .PARAMETER SequenceNumber
        Remove um restore point especifico pelo numero de sequencia.
    .PARAMETER All
        Remove todos os restore points.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByAge')]
    param(
        [Parameter(ParameterSetName = 'ByAge')]
        [int]$OlderThanDays,

        [Parameter(ParameterSetName = 'ByCount')]
        [int]$KeepLast,

        [Parameter(ParameterSetName = 'ById')]
        [int]$SequenceNumber,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All
    )

    $points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    if (-not $points) { Write-Warning "Nenhum restore point encontrado."; return }

    $toRemove = switch ($PSCmdlet.ParameterSetName) {
        'ByAge' {
            $cutoff = (Get-Date).AddDays(-$OlderThanDays)
            $points | Where-Object {
                try {
                    $dt = [System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)
                    $dt -lt $cutoff
                } catch { $false }
            }
        }
        'ByCount' {
            $sorted = $points | Sort-Object SequenceNumber -Descending
            $sorted | Select-Object -Skip $KeepLast
        }
        'ById' {
            $points | Where-Object { $_.SequenceNumber -eq $SequenceNumber }
        }
        'All' { $points }
    }

    if (-not $toRemove) { Write-Warning "Nenhum restore point para remover."; return }

    $count = ($toRemove | Measure-Object).Count
    if ($PSCmdlet.ShouldProcess("$count restore point(s)", 'Remover')) {
        # A saida do vssadmin nao traz o SequenceNumber; a remocao usa a API oficial
        # SRRemoveRestorePoint e so conta o que de fato foi removido.
        $removedCount = 0
        $failedCount = 0
        foreach ($pt in $toRemove) {
            try {
                $code = Invoke-SRRemoveRestorePoint -SequenceNumber ([int]$pt.SequenceNumber)
                if ($code -eq 0) {
                    $removedCount++
                }
                else {
                    $failedCount++
                    Write-Warning ("Falha ao remover restore point {0}: codigo Win32 {1}." -f $pt.SequenceNumber, $code)
                }
            } catch {
                $failedCount++
                Write-Warning "Falha ao remover restore point $($pt.SequenceNumber): $($_.Exception.Message)"
            }
        }
        Write-Output "$removedCount de $count restore point(s) removido(s)."
        if ($failedCount -gt 0) {
            Write-Error "$failedCount restore point(s) nao foram removidos."
        }
    }
}
