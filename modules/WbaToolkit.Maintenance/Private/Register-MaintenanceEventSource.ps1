function Register-MaintenanceEventSource {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Source
    )
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($Source)) {
            New-EventLog -LogName Application -Source $Source -ErrorAction Stop
        }
    }
    catch {
        Write-Warning "Nao foi possivel registrar fonte de eventos '$Source': $($_.Exception.Message)"
    }
}
