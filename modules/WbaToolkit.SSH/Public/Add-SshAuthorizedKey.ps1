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
        $matched = Get-Content -LiteralPath $PublicKeyPath -ErrorAction Stop | Where-Object {
            $_ -match '^\s*(ssh-rsa|ssh-ed25519|ecdsa-sha2|ssh-dss)'
        } | Select-Object -First 1
        if ($matched) {
            $PublicKey = $matched.Trim()
        }
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
    $isAdmin = Test-SshUserIsAdmin -UserName $UserName

    if ($isAdmin) {
        $keyFile = $paths.AdminAuthorizedKeys
        $adminDir = Split-Path -Parent $keyFile
        if (-not (Test-Path -LiteralPath $adminDir)) {
            New-Item -ItemType Directory -Path $adminDir -Force | Out-Null
        }
    }
    else {
        $userDir = Join-Path (Get-SshUserProfilePath -UserName $UserName) '.ssh'
        if (-not (Test-Path -LiteralPath $userDir)) {
            New-Item -ItemType Directory -Path $userDir -Force | Out-Null
        }
        $keyFile = Join-Path $userDir 'authorized_keys'
    }

    if (Test-Path -LiteralPath $keyFile) {
        $existing = Get-Content -LiteralPath $keyFile -ErrorAction Stop
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
        # UTF-8 sem BOM: no Windows PowerShell 5.1, Add-Content -Encoding UTF8 cria o arquivo com BOM e o
        # OpenSSH deixa de reconhecer a primeira chave. Se a ultima linha nao terminar em quebra de linha,
        # a chave nova iria colada nela.
        $entry = $PublicKey.Trim()
        $prefix = ''
        if (Test-Path -LiteralPath $keyFile -PathType Leaf) {
            $current = [System.IO.File]::ReadAllText($keyFile)
            if ($current.Length -gt 0 -and -not $current.EndsWith("`n")) { $prefix = "`r`n" }
        }
        [System.IO.File]::AppendAllText($keyFile, "$prefix$entry`r`n", (New-Object System.Text.UTF8Encoding($false)))

        if ($isAdmin -and $keyFile -eq $paths.AdminAuthorizedKeys) {
            $acl = Get-Acl -LiteralPath $keyFile
            $acl.SetAccessRuleProtection($true, $false)

            # SIDs bem-conhecidos (ADR 0034): 'SYSTEM' e 'Administrators' nao resolvem no Windows em portugues.
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
            $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $systemSid, 'FullControl', 'Allow')
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $adminSid, 'FullControl', 'Allow')
            $acl.SetAccessRule($systemRule)
            $acl.SetAccessRule($adminRule)
            Set-Acl -LiteralPath $keyFile -AclObject $acl -ErrorAction Stop
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
