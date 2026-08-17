# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxExclusaoDefender {
    <#
    .SYNOPSIS
        Checagem de saude: exclusao do Dropbox no Windows Defender.

    .DESCRIPTION
        AVISO se nao for possivel verificar (cmdlet ausente) ou se algum dos
        caminhos informados nao estiver na lista de exclusoes.

    .PARAMETER Paths
        Caminho(s) raiz do Dropbox a verificar na lista de exclusoes.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $preference = Get-DropboxDefenderPreference
    if ($null -eq $preference) {
        return New-DropboxCheckResult -Categoria 'Seguranca' -Nome 'Exclusao no Defender' -Status 'AVISO' `
            -Detalhe 'Nao foi possivel verificar as exclusoes do Windows Defender.' -Penalidade 5
    }

    $exclusions = @($preference.ExclusionPath)
    $missing = @($Paths | Where-Object { $_ -notin $exclusions })

    if ($missing.Count -eq 0) {
        return New-DropboxCheckResult -Categoria 'Seguranca' -Nome 'Exclusao no Defender' -Status 'OK' `
            -Detalhe 'Todos os caminhos do Dropbox estao na lista de exclusoes do Defender.'
    }

    return New-DropboxCheckResult -Categoria 'Seguranca' -Nome 'Exclusao no Defender' -Status 'AVISO' `
        -Detalhe "Caminho(s) do Dropbox nao excluidos do Defender: $($missing -join '; ')." `
        -Recomendacao 'Use -ExcluirDoDefender em modo Assistido para adicionar a exclusao.' `
        -Penalidade 5
}
