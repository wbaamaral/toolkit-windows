function Get-FileHashSha256 {
    <#
    .SYNOPSIS
        Calcula o hash SHA256 de um arquivo e opcionalmente salva em arquivo .sha256sum.

    .DESCRIPTION
        Funcao reutilizavel para gerar hash SHA256 de qualquer arquivo.
        Pode retornar apenas o hash ou salvar em arquivo .sha256sum para verificacao futura.

    .PARAMETER Path
        Caminho do arquivo para calcular o hash.

    .PARAMETER SaveToFile
        Se $true, salva o hash em arquivo .sha256sum no mesmo diretorio.

    .PARAMETER Quiet
        Se $true, nao exibe mensagem de sucesso.

    .OUTPUTS
        String com o hash SHA256.

    .EXAMPLE
        $hash = Get-FileHashSha256 -Path "C:\backup\drivers.zip"

    .EXAMPLE
        Get-FileHashSha256 -Path "C:\backup\drivers.zip" -SaveToFile

    .EXAMPLE
        $hash = Get-FileHashSha256 -Path "C:\backup\drivers.zip" -SaveToFile -Quiet
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$SaveToFile,

        [switch]$Quiet
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo nao encontrado: $Path"
    }

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash

    if ($SaveToFile) {
        $hashFilePath = "$Path.sha256sum"
        $fileName = Split-Path -Leaf $Path
        $hashContent = "$hash  $fileName"
        [System.IO.File]::WriteAllText($hashFilePath, $hashContent, [System.Text.UTF8Encoding]::new($false))

        if (-not $Quiet) {
            Write-Verbose "Hash SHA256 salvo: $hashFilePath"
        }
    }

    return $hash
}
