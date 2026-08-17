# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxConectividade {
    <#
    .SYNOPSIS
        Checagem de saude: conectividade TCP 443 com os hosts do Dropbox.

    .DESCRIPTION
        FALHA critica se nenhum dos destinos responder. AVISO se algum falhar.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param()

    $targets = @('www.dropbox.com', 'api.dropboxapi.com', 'client-cdn.dropbox.com')
    $failed = @($targets | Where-Object { -not (Test-DropboxTcpPort -HostName $_ -Port 443) })

    if ($failed.Count -eq $targets.Count) {
        return New-DropboxCheckResult -Categoria 'Rede' -Nome 'Conectividade Dropbox (TCP 443)' -Status 'FALHA' `
            -Detalhe "Nenhum dos destinos respondeu na porta 443: $($targets -join ', ')." `
            -Recomendacao 'Verifique firewall, proxy e conectividade geral com a internet.' `
            -Penalidade 40 -Critico
    }

    if ($failed.Count -gt 0) {
        return New-DropboxCheckResult -Categoria 'Rede' -Nome 'Conectividade Dropbox (TCP 443)' -Status 'AVISO' `
            -Detalhe "Falha ao conectar em: $($failed -join ', ')." `
            -Recomendacao 'Verifique firewall e regras de proxy para esses destinos.' `
            -Penalidade 15
    }

    return New-DropboxCheckResult -Categoria 'Rede' -Nome 'Conectividade Dropbox (TCP 443)' -Status 'OK' `
        -Detalhe "Conectividade TCP 443 validada com $($targets -join ', ')."
}
