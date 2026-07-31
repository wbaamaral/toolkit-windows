function Get-SshAuthorizedKey {
    <#
    .SYNOPSIS
        Lista chaves publicas no authorized_keys.

    .DESCRIPTION
        Retorna todas as chaves publicas do authorized_keys do usuario
        ou do administrators_authorized_keys.

    .PARAMETER UserName
        Nome do usuario. Padrao: usuario atual.

    .OUTPUTS
        Array de PSCustomObject com: Index, Type, Fingerprint, Comment, FullKey.

    .EXAMPLE
        Get-SshAuthorizedKey

    .EXAMPLE
        Get-SshAuthorizedKey -UserName 'joao'
    #>
    [CmdletBinding()]
    param(
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
        return @()
    }

    $lines = Get-Content -LiteralPath $keyFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*(ssh-rsa|ssh-ed25519|ecdsa-sha2|ssh-dss)\s+' }

    $index = 0
    $results = foreach ($line in $lines) {
        $parts = $line.Trim() -split '\s+'
        $type = if ($parts.Count -ge 1) { $parts[0] } else { 'unknown' }
        $keyData = if ($parts.Count -ge 2) { $parts[1] } else { '' }
        $comment = if ($parts.Count -ge 3) { $parts[2] } else { '' }

        $fingerprint = if ($keyData.Length -ge 16) {
            $keyData.Substring(0, 16) + '...'
        } elseif ($keyData.Length -ge 8) {
            $keyData.Substring(0, 8) + '...'
        } else { $keyData }

        [pscustomobject]@{
            Index       = $index
            Type        = $type
            Fingerprint = $fingerprint
            Comment     = $comment
            FullKey     = $line.Trim()
        }
        $index++
    }

    @($results)
}
