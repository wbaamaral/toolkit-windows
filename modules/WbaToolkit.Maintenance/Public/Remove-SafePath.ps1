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

    .PARAMETER AllowedRoot
        Lista de raizes permitidas. O caminho informado DEVE estar dentro de uma delas,
        senao a operacao e recusada. Protege contra remocao acidental de diretorios
        criticos. O padrao cobre as areas de limpeza usuais do Windows.

    .EXAMPLE
        Remove-SafePath -Path "C:\Windows\Temp"

    .EXAMPLE
        Remove-SafePath -Path "C:\Windows\Logs" -OlderThanDays 30

    .NOTES
        Autor: wbaamaral
        Seguranca: canonicaliza o caminho (anti path traversal), recusa raizes de volume
        e diretorios criticos (C:\, %SystemRoot%, C:\Users) e exige que o alvo esteja
        dentro de AllowedRoot. Suporta -WhatIf (ConfirmImpact Medium: nao pergunta a cada
        chamada, pois e usado em lote na limpeza; a seguranca vem da validacao de caminho).
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$OlderThanDays = 0,

        [Parameter()]
        [string[]]$AllowedRoot = @(
            "$env:TEMP"
            "$env:SystemRoot\Temp"
            "$env:SystemRoot\Minidump"
            "$env:SystemRoot\Logs"
            "$env:SystemRoot\SoftwareDistribution"
            "$env:ProgramData\Microsoft\Windows\WER"
            "$env:SystemDrive\Users"
        )
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Verbose "Remove-SafePath: caminho inexistente, nada a fazer: '$Path'."
        return
    }

    # Canonicaliza (resolve '.', '..' e barras) para impedir path traversal.
    try {
        $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath.TrimEnd('\')
    }
    catch {
        Write-Warning "Remove-SafePath: nao foi possivel resolver '$Path'. Operacao abortada."
        return
    }

    # Recusa raizes de volume e diretorios criticos.
    $systemRoot  = if ($env:SystemRoot)  { $env:SystemRoot.TrimEnd('\') }  else { '' }
    $systemDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\') } else { '' }
    $usersRoot   = if ($env:SystemDrive) { (Join-Path $env:SystemDrive 'Users').TrimEnd('\') } else { '' }
    if ($full -match '^[A-Za-z]:\\?$' -or
        $full.Length -le 3 -or
        ($systemRoot  -and $full -ieq $systemRoot) -or
        ($systemDrive -and $full -ieq $systemDrive) -or
        ($usersRoot   -and $full -ieq $usersRoot)) {
        Write-Warning "Remove-SafePath: recusado por seguranca (raiz ou diretorio critico): '$full'."
        return
    }

    # Exige que o alvo esteja DENTRO de uma raiz permitida. O separador no StartsWith
    # evita correspondencia parcial (ex.: 'C:\Temp2' nao casa 'C:\Temp').
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $isAllowed = $false
    foreach ($root in $AllowedRoot) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $rootFull = ([System.IO.Path]::GetFullPath($root)).TrimEnd($sep)
        if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($rootFull + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
            $isAllowed = $true
            break
        }
    }
    if (-not $isAllowed) {
        Write-Warning "Remove-SafePath: recusado, '$full' esta fora das raizes permitidas."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($full, 'Remover conteudo')) {
        return
    }

    # Excecao consciente a regra de nao silenciar: a limpeza em lote de areas temporarias
    # encontra rotineiramente arquivos em uso/bloqueados; o melhor esforco por item e o
    # comportamento correto aqui (ver tratamento-erros-idempotencia, secao 13.2).
    if ($OlderThanDays -gt 0) {
        $limit = (Get-Date).AddDays(-$OlderThanDays)
        Get-ChildItem -LiteralPath $full -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and $_.LastWriteTime -lt $limit
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}
