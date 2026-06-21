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

    $conteudo = Read-RegFileContent -Path $RegFilePath

    # Reescreve todas as referencias de hive do usuario para o ponto de montagem ativo,
    # cobrindo as tres formas que um .reg pode usar. Sem isso, HKEY_CURRENT_USER seria
    # importado no hive do usuario logado em vez do perfil Default.
    $alvo    = "HKEY_USERS\$MountPoint"
    $padroes = @(
        'hkey_users\\\.default',   # HKEY_USERS\.DEFAULT
        'hkey_users\\default',     # HKEY_USERS\DEFAULT (forma usada pelo toolkit)
        'hkey_current_user'        # HKEY_CURRENT_USER
    )
    $substituido = $conteudo
    $totalSubs   = 0
    foreach ($padrao in $padroes) {
        $totalSubs += [System.Text.RegularExpressions.Regex]::Matches(
            $substituido, $padrao,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
        $substituido = [System.Text.RegularExpressions.Regex]::Replace(
            $substituido, $padrao, $alvo,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    # Garante que o .reg referenciava o hive do usuario; importar sem substituir
    # escreveria no hive ativo (HKCU do usuario logado) em vez do perfil Default.
    if ($totalSubs -eq 0) {
        throw ("Arquivo .reg lido com sucesso, mas nenhuma referencia de hive de usuario foi encontrada. " +
            "Importacao abortada para evitar escrita fora do perfil Default.")
    }

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
