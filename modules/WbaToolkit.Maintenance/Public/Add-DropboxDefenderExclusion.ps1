# Projeto: wba-toolkit
# Autor: wbaamaral

function Add-DropboxDefenderExclusion {
    <#
    .SYNOPSIS
        Adiciona caminho(s) do Dropbox as exclusoes do Windows Defender.

    .DESCRIPTION
        Chama Add-MpPreference -ExclusionPath. Requer privilegio de Administrador
        -- a verificacao de elevacao e responsabilidade do script wrapper antes de
        chamar esta funcao. Trata com clareza o caso de Add-MpPreference ausente
        (Defender desabilitado/nao instalado) ou acesso negado.

    .PARAMETER Path
        Caminho(s) a excluir da varredura do Defender.

    .EXAMPLE
        Add-DropboxDefenderExclusion -Path 'C:\Users\usuario\Dropbox'

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com Success e Message.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    try {
        Add-MpPreference -ExclusionPath $Path -ErrorAction Stop
        return [pscustomobject]@{
            Success = $true
            Message = "Exclusao adicionada para: $($Path -join '; ')."
        }
    }
    catch {
        Write-Verbose "Falha ao adicionar exclusao no Defender: $($_.Exception.Message)"
        return [pscustomobject]@{
            Success = $false
            Message = "Falha ao adicionar exclusao no Defender (Defender ausente, desabilitado ou acesso negado): $($_.Exception.Message)"
        }
    }
}
