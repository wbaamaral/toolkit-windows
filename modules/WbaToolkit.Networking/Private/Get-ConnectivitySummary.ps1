function Get-ConnectivitySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Results
    )

    $grouped = $Results | Group-Object Classification

    [pscustomobject]@{
        Total         = @($Results).Count
        Success       = @($grouped | Where-Object Name -eq 'Success').Count
        Failed        = @($grouped | Where-Object Name -eq 'Failed').Count
        Warning       = @($grouped | Where-Object Name -eq 'Warning').Count
        Inconclusive  = @($grouped | Where-Object Name -eq 'Inconclusive').Count
        Skipped       = @($grouped | Where-Object Name -eq 'Skipped').Count
        Error         = @($grouped | Where-Object Name -eq 'Error').Count
    }
}
