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
    # A troca e feita so nos cabecalhos de chave ([...] e [-...]); valores que citam
    # HKEY_CURRENT_USER como texto nao sao alterados.
    $alvo    = "HKEY_USERS\$MountPoint"
    $opcoes  = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Multiline'
    $padrao  = '^(\s*\[-?)(hkey_users\\\.default|hkey_users\\default|hkey_current_user)(?=\\|\])'
    $totalSubs   = [System.Text.RegularExpressions.Regex]::Matches($conteudo, $padrao, $opcoes).Count
    $substituido = [System.Text.RegularExpressions.Regex]::Replace($conteudo, $padrao, ('$1' + $alvo.Replace('$', '$$')), $opcoes)

    # Garante que o .reg referenciava o hive do usuario; importar sem substituir
    # escreveria no hive ativo (HKCU do usuario logado) em vez do perfil Default.
    if ($totalSubs -eq 0) {
        throw ("Arquivo .reg lido com sucesso, mas nenhuma referencia de hive de usuario foi encontrada. " +
            "Importacao abortada para evitar escrita fora do perfil Default.")
    }

    # Toda chave precisa apontar para o hive montado: um .reg misto (ex.: HKCU + HKLM)
    # gravaria as chaves HKLM na maquina viva sem aviso.
    $foraDoPerfil = @([System.Text.RegularExpressions.Regex]::Matches($substituido, '^\s*\[-?([^\]\r\n]+)\]', $opcoes) |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { -not ($_.Equals($alvo, [System.StringComparison]::OrdinalIgnoreCase) -or
                             $_.StartsWith($alvo + '\', [System.StringComparison]::OrdinalIgnoreCase)) })
    if ($foraDoPerfil.Count -gt 0) {
        throw (("Arquivo .reg contem chaves fora do hive de usuario ({0}). Importacao abortada para evitar " +
            "escrita fora do perfil Default.") -f (($foraDoPerfil | Select-Object -First 5) -join '; '))
    }

    $tempPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "wba_sysprep_$([System.Guid]::NewGuid().ToString('N')).reg"
    )

    try {
        [System.IO.File]::WriteAllText($tempPath, $substituido, [System.Text.Encoding]::Unicode)

        # reg.exe em Windows PT-BR escreve em stderr mesmo em sucesso, gerando ErrorRecord
        # que dispara NativeCommandError com $ErrorActionPreference='Stop'. Suspender Stop
        # impede falso positivo; $LASTEXITCODE continua sendo a fonte de verdade.
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $saida = & reg import $tempPath 2>&1
        $ErrorActionPreference = $prevEAP

        if ($LASTEXITCODE -ne 0) {
            throw "reg import falhou (codigo $LASTEXITCODE): $($saida -join ' ')"
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
