function Invoke-W32tm {
    <#
    .SYNOPSIS
        Executa w32tm.exe e devolve codigo de saida e texto, sem depender de $LASTEXITCODE no chamador.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $output = & w32tm.exe @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}
