function New-SshHostKey {
    <#
    .SYNOPSIS
        Gera ou regenera chaves de host do SSH.

    .DESCRIPTION
        Gera chaves de host usando ssh-keygen. Tipos suportados: ed25519 (recomendado),
        rsa (4096 bits), ecdsa. Chaves existentes sao preservadas a nao ser que -Force.

    .PARAMETER KeyType
        Tipo da chave: ed25519 (padrao), rsa, ecdsa.

    .PARAMETER Force
        Sobrescreve chave existente.

    .OUTPUTS
        PSCustomObject com: Success, KeyType, PublicKeyPath, PublicKey.

    .EXAMPLE
        New-SshHostKey

    .EXAMPLE
        New-SshHostKey -KeyType rsa -Force
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('ed25519', 'rsa', 'ecdsa')]
        [string]$KeyType = 'ed25519',

        [switch]$Force
    )

    if (-not (Test-IsAdministrator)) {
        [pscustomobject]@{
            Success = $false
            Message = 'A geracao de chaves de host exige privilegios administrativos.'
        }
        return
    }

    $paths = Get-SshConfigPath
    $keyFileName = "ssh_host_${KeyType}_key"
    $keyPath = Join-Path $paths.HostKeysDir $keyFileName
    $pubKeyPath = "${keyPath}.pub"

    if ((Test-Path -LiteralPath $keyPath) -and -not $Force) {
        [pscustomobject]@{
            Success       = $true
            KeyType       = $KeyType
            PublicKeyPath = $pubKeyPath
            PublicKey     = (Get-Content -LiteralPath $pubKeyPath -ErrorAction SilentlyContinue)
            Message       = 'Chave existente preservada. Use -Force para regenerar.'
            Generated     = $false
        }
        return
    }

    if ((Test-Path -LiteralPath $keyPath) -and $Force) {
        $backupPath = "${keyPath}.bak.$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
        Copy-Item -LiteralPath $keyPath -Destination $backupPath -Force
        Copy-Item -LiteralPath $pubKeyPath -Destination "${backupPath}.pub" -Force
        Write-Verbose "Backup da chave existente: $backupPath"
    }

    $bits = if ($KeyType -eq 'rsa') { '-b 4096' } else { '' }
    $sshKeygenArgs = @('-t', $KeyType, '-f', "`"$keyPath`"", '-N', '""', '-q')
    if ($bits) { $sshKeygenArgs = @('-t', $KeyType, '-b', '4096', '-f', "`"$keyPath`"", '-N', '""', '-q') }

    try {
        $process = Start-Process -FilePath 'ssh-keygen.exe' `
            -ArgumentList ($sshKeygenArgs -join ' ') `
            -Wait -NoNewWindow -PassThru -ErrorAction Stop

        if ($process.ExitCode -ne 0) {
            throw "ssh-keygen retornou codigo $($process.ExitCode)"
        }

        $pubKey = Get-Content -LiteralPath $pubKeyPath -ErrorAction SilentlyContinue

        [pscustomobject]@{
            Success       = $true
            KeyType       = $KeyType
            PublicKeyPath = $pubKeyPath
            PublicKey     = $pubKey
            Message       = "Chave $KeyType gerada com sucesso."
            Generated     = $true
        }
    }
    catch {
        [pscustomobject]@{
            Success       = $false
            KeyType       = $KeyType
            PublicKeyPath = $pubKeyPath
            PublicKey     = $null
            Message       = "Falha ao gerar chave: $($_.Exception.Message)"
            Generated     = $false
        }
    }
}
