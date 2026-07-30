function Add-SshAuthorizedKey {
    <#
    .SYNOPSIS
        Adiciona chave publica ao authorized_keys com ACL correto.

    .DESCRIPTION
        Adiciona uma chave publica SSH ao arquivo authorized_keys do usuario.
        Para contas administradoras, salva em administrators_authorized_keys.
        Configura ACL: SYSTEM + Administrators (Full), Dono (Read).

    .PARAMETER PublicKey
        Conteudo da chave publica (linha completa ssh-rsa/ssh-ed25519/etc).

    .PARAMETER PublicKeyPath
        Caminho do arquivo .pub para ler a chave.

    .PARAMETER UserName
        Nome do usuario. Padrao: usuario atual.

    .OUTPUTS
        PSCustomObject com: Success, Message, KeyFile.

    .EXAMPLE
        Add-SshAuthorizedKey -PublicKey 'ssh-ed25519 AAAA... user@host'

    .EXAMPLE
        Add-SshAuthorizedKey -PublicKeyPath 'C:\chaves\id_ed25519.pub' -UserName 'joao'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$PublicKey,

        [Parameter(Mandatory = $false)]
        [string]$PublicKeyPath,

        [string]$UserName
    )

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $UserName = $env:USERNAME
    }

    if ([string]::IsNullOrWhiteSpace($PublicKey) -and -not [string]::IsNullOrWhiteSpace($PublicKeyPath)) {
        if (-not (Test-Path -LiteralPath $PublicKeyPath -PathType Leaf)) {
            [pscustomobject]@{
                Success = $false
                Message = "Arquivo de chave nao encontrado: $PublicKeyPath"
            }
            return
        }
        $PublicKey = (Get-Content -LiteralPath $PublicKeyPath -ErrorAction SilentlyContinue | Where-Object {
            $_ -match '^\s*(ssh-rsa|ssh-ed25519|ecdsa-sha2|ssh-dss)'
        } | Select-Object -First 1).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($PublicKey)) {
        [pscustomobject]@{
            Success = $false
            Message = 'Chave publica nao fornecida ou invalida.'
        }
        return
    }

    if ($PublicKey -notmatch '^\s*(ssh-rsa|ssh-ed25519|ecdsa-sha2|ssh-dss)\s+') {
        [pscustomobject]@{
            Success = $false
            Message = 'Formato de chave publica invalido. Use: ssh-rsa AAAA... | ssh-ed25519 AAAA...'
        }
        return
    }

    $paths = Get-SshConfigPath
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin -and $UserName -ne $env:USERNAME) {
        $keyFile = $paths.AdminAuthorizedKeys
    }
    else {
        $userDir = Join-Path "C:\Users\$UserName" '.ssh'
        if (-not (Test-Path -LiteralPath $userDir)) {
            New-Item -ItemType Directory -Path $userDir -Force | Out-Null
        }
        $keyFile = Join-Path $userDir 'authorized_keys'
    }

    if (Test-Path -LiteralPath $keyFile) {
        $existing = Get-Content -LiteralPath $keyFile -ErrorAction SilentlyContinue
        foreach ($line in $existing) {
            if ($line.Trim() -eq $PublicKey.Trim()) {
                [pscustomobject]@{
                    Success = $true
                    Message = 'Chave publica ja existe no authorized_keys.'
                    KeyFile = $keyFile
                }
                return
            }
        }
    }

    try {
        $entry = $PublicKey.Trim()
        Add-Content -LiteralPath $keyFile -Value $entry -Encoding UTF8 -ErrorAction Stop

        if ($isAdmin -and $keyFile -eq $paths.AdminAuthorizedKeys) {
            $acl = Get-Acl -LiteralPath $keyFile
            $acl.SetAccessRuleProtection($true, $false)

            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'SYSTEM', 'FullControl', 'Allow')
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'Administrators', 'FullControl', 'Allow')
            $acl.SetAccessRule($systemRule)
            $acl.SetAccessRule($adminRule)
            Set-Acl -LiteralPath $keyFile -AclObject $acl -ErrorAction SilentlyContinue
        }

        [pscustomobject]@{
            Success = $true
            Message = "Chave publica adicionada a: $keyFile"
            KeyFile = $keyFile
        }
    }
    catch {
        [pscustomobject]@{
            Success = $false
            Message = "Falha ao adicionar chave: $($_.Exception.Message)"
            KeyFile = $keyFile
        }
    }
}
