function Resolve-PortSpecification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PortSpec,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$MaxPorts = 1024
    )

    $ports = New-Object 'System.Collections.Generic.List[int]'
    $tokens = $PortSpec -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($token in $tokens) {
        if ($token -match '^(?<Start>\d+)-(?<End>\d+)$') {
            $start = [int]$Matches.Start
            $end = [int]$Matches.End

            if ($start -lt 1 -or $start -gt 65535 -or $end -lt 1 -or $end -gt 65535) {
                throw "Porta fora do intervalo valido: $token"
            }

            if ($start -gt $end) {
                throw "Range de portas invalido: $token"
            }

            foreach ($port in $start..$end) {
                $ports.Add($port)
            }
        }
        elseif ($token -match '^\d+$') {
            $port = [int]$token
            if ($port -lt 1 -or $port -gt 65535) {
                throw "Porta fora do intervalo valido: $token"
            }

            $ports.Add($port)
        }
        else {
            throw "Especificacao de porta invalida: $token"
        }
    }

    $resolvedPorts = @($ports | Sort-Object -Unique)
    if ($resolvedPorts.Count -eq 0) {
        throw 'Nenhuma porta valida foi informada.'
    }

    if ($resolvedPorts.Count -gt $MaxPorts) {
        throw "A especificacao gerou $($resolvedPorts.Count) portas. O limite atual e $MaxPorts."
    }

    $resolvedPorts
}
