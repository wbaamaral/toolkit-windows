function Format-ServiceResult {
    <#
    .SYNOPSIS
        Padroniza o retorno de operacoes de servico.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$ServiceName = '',

        [string[]]$Changes = @()
    )

    [pscustomobject]@{
        Success     = $Success
        Message     = $Message
        ServiceName = $ServiceName
        Changes     = @($Changes)
    }
}
