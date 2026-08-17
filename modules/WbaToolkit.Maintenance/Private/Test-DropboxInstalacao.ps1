# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxInstalacao {
    <#
    .SYNOPSIS
        Checagem de saude: instalacao/conta do Dropbox valida.

    .DESCRIPTION
        FALHA critica se o caminho informado nao existir. AVISO se a pasta existir
        mas nao houver conta confirmada via info.json.

    .PARAMETER Installations
        Resultado de Get-DropboxInstallation.

    .PARAMETER Path
        Caminho raiz do Dropbox sendo diagnosticado.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Installations = @(),

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return New-DropboxCheckResult -Categoria 'Instalacao' -Nome 'Pasta Dropbox' -Status 'FALHA' `
            -Detalhe "Caminho informado nao existe: $Path" `
            -Recomendacao 'Verifique se o Dropbox esta instalado e a pasta ainda existe.' `
            -Penalidade 40 -Critico
    }

    if (@($Installations).Count -eq 0) {
        return New-DropboxCheckResult -Categoria 'Instalacao' -Nome 'Conta Dropbox' -Status 'AVISO' `
            -Detalhe 'Nao foi possivel confirmar a conta via info.json, mas a pasta informada existe.' `
            -Recomendacao 'Verifique se o cliente Dropbox esta instalado corretamente.' `
            -Penalidade 10
    }

    return New-DropboxCheckResult -Categoria 'Instalacao' -Nome 'Conta Dropbox' -Status 'OK' `
        -Detalhe "Instalacao valida: $(@($Installations).Count) conta(s) detectada(s) via info.json."
}
