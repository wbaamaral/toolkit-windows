function Remove-RestorePoint {
    <#
    .SYNOPSIS
        Remove pontos de restauracao.
    .DESCRIPTION
        Remove restore points por idade, quantidade ou sequencia especifica.
        Usa vssadmin delete shadows para remocao.
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
        foreach ($pt in $toRemove) {
            try {
                $shadowId = vssadmin list shadows 2>&1 | Select-String -Pattern "SeqID: $($pt.SequenceNumber)" -Context 0,2
                if ($shadowId) {
                    $idLine = ($shadowId -split "`n" | Where-Object { $_ -match 'Shadow Copy ID:' }) | Select-Object -First 1
                    if ($idLine -match '\{.+\}') {
                        $guid = $Matches[0]
                        & vssadmin delete shadows /shadow=$guid /quiet 2>&1 | Out-Null
                    }
                }
            } catch {
                Write-Warning "Falha ao remover restore point $($pt.SequenceNumber): $_"
            }
        }
        Write-Output "$count restore point(s) removido(s)."
    }
}
