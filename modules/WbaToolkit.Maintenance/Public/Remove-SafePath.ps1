function Remove-SafePath {
    <#
    .SYNOPSIS
        Remove com seguranca arquivos de um caminho, opcionalmente filtrando por idade.

    .DESCRIPTION
        Remove arquivos e subdiretorios do caminho especificado. Quando OlderThanDays
        for informado, remove apenas arquivos com LastWriteTime anterior ao numero de
        dias indicado. Nao lanca excecao se o caminho nao existir.

    .PARAMETER Path
        Caminho do diretorio a ser limpo.

    .PARAMETER OlderThanDays
        Quando maior que zero, remove apenas arquivos mais antigos que este numero de
        dias. Padrao: 0 (remove tudo).

    .EXAMPLE
        Remove-SafePath -Path "C:\Windows\Temp"

    .EXAMPLE
        Remove-SafePath -Path "C:\Windows\Logs" -OlderThanDays 30

    .NOTES
        Autor: wbaamaral
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$OlderThanDays = 0
    )

    if (-not (Test-Path $Path)) {
        return
    }

    if ($OlderThanDays -gt 0) {
        Get-ChildItem $Path -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-$OlderThanDays)
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem $Path -Force -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}
