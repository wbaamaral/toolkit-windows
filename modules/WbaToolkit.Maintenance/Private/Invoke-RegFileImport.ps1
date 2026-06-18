function Invoke-RegFileImport {
    <#
    .SYNOPSIS
        Importa um arquivo .reg substituindo o caminho do hive pelo ponto de montagem ativo.

    .PARAMETER RegFilePath
        Caminho do arquivo .reg a importar.

    .PARAMETER MountPoint
        Nome do ponto de montagem no HKEY_USERS onde o hive esta carregado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegFilePath,

        [Parameter(Mandatory = $true)]
        [string]$MountPoint
    )

    $conteudo = [System.IO.File]::ReadAllText($RegFilePath, [System.Text.Encoding]::UTF8)

    $substituido = [System.Text.RegularExpressions.Regex]::Replace(
        $conteudo,
        'hkey_users\\default',
        "HKEY_USERS\\$MountPoint",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $tempPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "wba_sysprep_$([System.Guid]::NewGuid().ToString('N')).reg"
    )

    try {
        [System.IO.File]::WriteAllText($tempPath, $substituido, [System.Text.Encoding]::Unicode)

        $saida = & reg import $tempPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "reg import falhou (codigo $LASTEXITCODE): $saida"
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
