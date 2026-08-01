function Remove-SshAuthorizedKey {
    <#
    .SYNOPSIS
        Remove uma chave publica do authorized_keys.

    .DESCRIPTION
        Remove uma chave publica especifica pelo conteudo (fingerprint parcial)
        ou pelo indice na lista.

    .PARAMETER PublicKey
        Trecho da chave publica para identificar (fingerprint ou inicio da linha).

    .PARAMETER Index
        Indice da chave na lista (0-based). Use Get-SshAuthorizedKey para listar.

    .PARAMETER UserName
        Nome do usuario. Padrao: usuario atual.

    .OUTPUTS
        PSCustomObject com: Success, Message, Removed.

    .EXAMPLE
        Remove-SshAuthorizedKey -PublicKey 'ssh-ed25519 AAAA3char...'

    .EXAMPLE
        Remove-SshAuthorizedKey -Index 0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$PublicKey,
        [int]$Index = -1,
        [string]$UserName
    )

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $UserName = $env:USERNAME
    }

    $paths = Get-SshConfigPath
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin -and $UserName -ne $env:USERNAME) {
        $keyFile = $paths.AdminAuthorizedKeys
    }
    else {
        $keyFile = Join-Path "C:\Users\$UserName\.ssh" 'authorized_keys'
    }

    if (-not (Test-Path -LiteralPath $keyFile -PathType Leaf)) {
        [pscustomobject]@{
            Success = $false
            Message = "Arquivo authorized_keys nao encontrado: $keyFile"
            Removed = $false
        }
        return
    }

    $lines = @(Get-Content -LiteralPath $keyFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*(ssh-rsa|ssh-ed25519|ecdsa-sha2|ssh-dss)\s+' })

    if ($lines.Count -eq 0) {
        [pscustomobject]@{
            Success = $true
            Message = 'Nenhuma chave publica encontrada no authorized_keys.'
            Removed = $false
        }
        return
    }

    $removed = $false
    $newLines = [System.Collections.Generic.List[string]]::new()

    if ($Index -ge 0 -and $Index -lt $lines.Count) {
        $target = $lines[$Index]
        foreach ($line in $lines) {
            if ($line -eq $target) {
                $removed = $true
                continue
            }
            $newLines.Add($line)
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PublicKey)) {
        foreach ($line in $lines) {
            if ($line.Trim() -like "*$($PublicKey.Trim())*") {
                $removed = $true
                continue
            }
            $newLines.Add($line)
        }
    }
    else {
        [pscustomobject]@{
            Success = $false
            Message = 'Fornecca -PublicKey ou -Index para identificar a chave a remover.'
            Removed = $false
        }
        return
    }

    if (-not $removed) {
        [pscustomobject]@{
            Success = $false
            Message = 'Chave publica nao encontrada no authorized_keys.'
            Removed = $false
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($keyFile, 'Remover chave autorizada SSH')) {
        return [pscustomobject]@{ Success = $true; Message = 'Remocao de chave ignorada por WhatIf.'; Removed = $false }
    }

    try {
        $newLines | Set-Content -LiteralPath $keyFile -Encoding UTF8 -ErrorAction Stop
        [pscustomobject]@{
            Success = $true
            Message = 'Chave publica removida com sucesso.'
            Removed = $true
        }
    }
    catch {
        [pscustomobject]@{
            Success = $false
            Message = "Falha ao gravar authorized_keys: $($_.Exception.Message)"
            Removed = $false
        }
    }
}
