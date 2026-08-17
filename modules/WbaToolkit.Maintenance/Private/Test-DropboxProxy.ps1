# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxProxy {
    <#
    .SYNOPSIS
        Checagem de saude: proxy do sistema configurado (WinHTTP).

    .DESCRIPTION
        Sempre AVISO informativo -- proxy configurado nao e necessariamente um
        problema, mas e relevante para o diagnostico quando a conectividade falha.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param()

    $result = Get-DropboxProxyConfiguration
    $output = [string]$result.Output

    if ($output -match '(?i)direct access|acesso direto|direto\s*\(sem proxy\)') {
        return New-DropboxCheckResult -Categoria 'Rede' -Nome 'Proxy do sistema' -Status 'OK' `
            -Detalhe 'Nenhum proxy configurado no WinHTTP (acesso direto).'
    }

    if (-not [string]::IsNullOrWhiteSpace($output)) {
        return New-DropboxCheckResult -Categoria 'Rede' -Nome 'Proxy do sistema' -Status 'AVISO' `
            -Detalhe "Proxy do sistema configurado. Saida de 'netsh winhttp show proxy': $output" `
            -Recomendacao 'Se a conectividade com o Dropbox falhar, verifique se o proxy libera os hosts do Dropbox.' `
            -Penalidade 5
    }

    return New-DropboxCheckResult -Categoria 'Rede' -Nome 'Proxy do sistema' -Status 'AVISO' `
        -Detalhe 'Nao foi possivel determinar a configuracao de proxy do sistema.' -Penalidade 5
}
