function New-SshUserKey {
    <#
    .SYNOPSIS
        Gera par de chaves SSH para um usuario.

    .DESCRIPTION
        Gera par de chaves (privada + publica) no .ssh do usuario especificado.
        Tipos suportados: ed25519 (recomendado), rsa, ecdsa.

    .PARAMETER UserName
        Nome do usuario. Padrao: usuario atual.

    .PARAMETER KeyType
        Tipo da chave: ed25519 (padrao), rsa, ecdsa.

    .PARAMETER KeyName
        Nome dos arquivos de chave. Padrao: id_<tipo>.

    .PARAMETER Force
        Sobrescreve chave existente.

    .OUTPUTS
        PSCustomObject com: Success, KeyPath, PublicKeyPath, PublicKey.

    .EXAMPLE
        New-SshUserKey

    .EXAMPLE
        New-SshUserKey -UserName 'joao' -KeyType rsa -KeyName 'id_rsa_corp'
    #>
    [CmdletBinding()]
    param(
        [string]$UserName,
        [ValidateSet('ed25519', 'rsa', 'ecdsa')]
        [string]$KeyType = 'ed25519',
        [string]$KeyName,
        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $UserName = $env:USERNAME
    }

    $userProfile = "C:\Users\$UserName"
    $sshDir = Join-Path $userProfile '.ssh'

    if (-not (Test-Path -LiteralPath $sshDir)) {
        try {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
            Write-Verbose "Diretorio .ssh criado: $sshDir"
        }
        catch {
            [pscustomobject]@{
                Success       = $false
                KeyPath       = $null
                PublicKeyPath = $null
                PublicKey     = $null
                Message       = "Falha ao criar .ssh: $($_.Exception.Message)"
            }
            return
        }
    }

    if ([string]::IsNullOrWhiteSpace($KeyName)) {
        $KeyName = "id_$KeyType"
    }

    $keyPath = Join-Path $sshDir $KeyName
    $pubKeyPath = "${keyPath}.pub"

    if ((Test-Path -LiteralPath $keyPath) -and -not $Force) {
        $pubKey = Get-Content -LiteralPath $pubKeyPath -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Success       = $true
            KeyPath       = $keyPath
            PublicKeyPath = $pubKeyPath
            PublicKey     = $pubKey
            Message       = 'Chave existente preservada. Use -Force para regenerar.'
            Generated     = $false
        }
        return
    }

    if ((Test-Path -LiteralPath $keyPath) -and $Force) {
        $backupPath = "${keyPath}.bak.$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
        Copy-Item -LiteralPath $keyPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $pubKeyPath -Destination "${backupPath}.pub" -Force -ErrorAction SilentlyContinue
        Write-Verbose "Backup da chave existente: $backupPath"
    }

    $sshKeygenArgs = @('-t', $KeyType, '-f', "`"$keyPath`"", '-N', '""', '-q')
    if ($KeyType -eq 'rsa') {
        $sshKeygenArgs = @('-t', $KeyType, '-b', '4096', '-f', "`"$keyPath`"", '-N', '""', '-q')
    }

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
            KeyPath       = $keyPath
            PublicKeyPath = $pubKeyPath
            PublicKey     = $pubKey
            Message       = "Par de chaves $KeyType gerado para $UserName."
            Generated     = $true
        }
    }
    catch {
        [pscustomobject]@{
            Success       = $false
            KeyPath       = $keyPath
            PublicKeyPath = $pubKeyPath
            PublicKey     = $null
            Message       = "Falha ao gerar chave: $($_.Exception.Message)"
            Generated     = $false
        }
    }
}
