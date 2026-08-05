function Exit-ToolkitProvisioningLock {
    <#
    .SYNOPSIS
        Libera o mutex adquirido por Enter-ToolkitProvisioningLock.

    .PARAMETER Mutex
        Objeto retornado por Enter-ToolkitProvisioningLock.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Threading.Mutex]$Mutex
    )

    try {
        $Mutex.ReleaseMutex()
    }
    catch [System.ApplicationException] {
        Write-Verbose "Mutex ja liberado ou nao pertence a esta thread: $($_.Exception.Message)"
    }
    finally {
        $Mutex.Dispose()
    }
}
