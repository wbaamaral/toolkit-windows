function Write-TextFileUtf8 {
    <#
    .SYNOPSIS
        Grava ou acrescenta texto em arquivo com encoding UTF-8 com BOM.

    .DESCRIPTION
        Escreve conteudo textual em um arquivo usando UTF-8 com BOM, garantindo
        compatibilidade com a convencao do toolkit. Suporta criacao de arquivo novo
        e modo de append para arquivos existentes.

    .PARAMETER Path
        Caminho completo do arquivo de destino.

    .PARAMETER Content
        Conteudo textual a gravar. Aceita string vazia.

    .PARAMETER Append
        Quando informado, acrescenta ao final do arquivo existente em vez de
        substituir. Se o arquivo nao existir, cria um novo.

    .EXAMPLE
        Write-TextFileUtf8 -Path 'C:\WBA\relatorio.txt' -Content $texto

        Grava o relatorio em UTF-8 com BOM.

    .EXAMPLE
        Write-TextFileUtf8 -Path 'C:\WBA\log.txt' -Content $linha -Append

        Acrescenta uma linha ao log existente.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content,

    [switch]$Append
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $encoding = Get-Utf8BomEncoding
    if ($Append -and (Test-Path -LiteralPath $Path)) {
        [System.IO.File]::AppendAllText($Path, $Content, $encoding)
    }
    else {
        [System.IO.File]::WriteAllText($Path, $Content, $encoding)
    }
}
