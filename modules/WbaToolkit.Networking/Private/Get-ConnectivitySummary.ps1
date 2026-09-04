function Get-ConnectivitySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Results
    )

    $grouped = $Results | Group-Object Classification
    $map = @{}
    foreach ($g in @($grouped)) {
        if ($null -ne $g -and $null -ne $g.Name) {
            $map[[string]$g.Name] = [int]$g.Count
        }
    }

    [pscustomobject]@{
        Total         = @($Results).Count
        Success       = if ($map.ContainsKey('Success')) { $map['Success'] } else { 0 }
        Failed        = if ($map.ContainsKey('Failed')) { $map['Failed'] } else { 0 }
        Warning       = if ($map.ContainsKey('Warning')) { $map['Warning'] } else { 0 }
        Inconclusive  = if ($map.ContainsKey('Inconclusive')) { $map['Inconclusive'] } else { 0 }
        Skipped       = if ($map.ContainsKey('Skipped')) { $map['Skipped'] } else { 0 }
        Error         = if ($map.ContainsKey('Error')) { $map['Error'] } else { 0 }
    }
}
