function Get-Utf8BomEncoding {
    <#
    .SYNOPSIS
        Retorna um objeto de encoding UTF-8 com BOM.

    .DESCRIPTION
        Retorna System.Text.UTF8Encoding configurado para emitir BOM (byte order mark),
        compativel com a convencao de arquivos PowerShell e relatórios do toolkit.

    .EXAMPLE
        $enc = Get-Utf8BomEncoding
        [System.IO.File]::WriteAllText($path, $content, $enc)

        Grava um arquivo texto em UTF-8 com BOM.

    .OUTPUTS
        System.Text.UTF8Encoding
    #>
    [CmdletBinding()]
    param()

    return [System.Text.UTF8Encoding]::new($true)
}
