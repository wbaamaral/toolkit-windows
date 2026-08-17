# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxDefenderPreference {
    <#
    .SYNOPSIS
        Retorna a preferencia atual do Windows Defender (Get-MpPreference).

    .DESCRIPTION
        Fronteira isolada e mockavel sobre Get-MpPreference. O cmdlet pode nao
        existir (Defender ausente/desabilitado) -- esse cenario e esperado e
        retorna $null em vez de lancar.

    .OUTPUTS
        Objeto retornado por Get-MpPreference ou $null
    #>
    [CmdletBinding()]
    param()

    try {
        return Get-MpPreference -ErrorAction Stop
    }
    catch {
        Write-Verbose "Get-MpPreference indisponivel ou falhou: $($_.Exception.Message)"
        return $null
    }
}
