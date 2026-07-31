function New-RestorePoint {
    <#
    .SYNOPSIS
        Cria um ponto de restauracao do sistema.
    .DESCRIPTION
        Cria um restore point usando Checkpoint-Computer.
        Nota: O Windows impoe um limite de 24h entre restore points manuais.
    .PARAMETER Description
        Descricao do restore point.
    .PARAMETER RestorePointType
        Tipo: APPLICATION_INSTALL ou MODIFY_SETTINGS. Padrao: APPLICATION_INSTALL.
    .OUTPUTS
        Objeto com resultado da operacao.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Description = 'WBA Toolkit Restore Point',
        [ValidateSet('APPLICATION_INSTALL', 'MODIFY_SETTINGS')]
        [string]$RestorePointType = 'APPLICATION_INSTALL'
    )

    if ($PSCmdlet.ShouldProcess('Sistema', "Criar restore point: $Description")) {
        try {
            Checkpoint-Computer -Description $Description -RestorePointType $RestorePointType -ErrorAction Stop
            Write-Output "Restore point criado: $Description"
            [pscustomobject]@{
                Success = $true
                Description = $Description
                CreatedAt = Get-Date
            }
        } catch {
            Write-Error "Falha ao criar restore point: $_"
            [pscustomobject]@{
                Success = $false
                Description = $Description
                Error = $_.Exception.Message
            }
        }
    }
}
