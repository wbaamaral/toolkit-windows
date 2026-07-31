function Get-SshdConfig {
    <#
    .SYNOPSIS
        Le e retorna o sshd_config como hashtable estruturado.

    .DESCRIPTION
        Parseia o arquivo sshd_config e retorna cada diretriz como par chave-valor.
        Diretivas duplicadas sao retornadas como array. Comentarios e linhas vazias
        sao ignorados.

    .PARAMETER Path
        Caminho do sshd_config. Padrao: %programdata%\ssh\sshd_config.

    .OUTPUTS
        PSCustomObject com: Config (hashtable), RawLines[], Path.

    .EXAMPLE
        $config = Get-SshdConfig
        $config.Config['Port']
        $config.Config['PasswordAuthentication']
    #>
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $paths = Get-SshConfigPath
        $Path = $paths.SshdConfig
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Config   = @{}
            RawLines = @()
            Path     = $Path
            Exists   = $false
        }
    }

    $rawLines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
    $config = @{}
    $currentMatch = $null

    foreach ($line in $rawLines) {
        $trimmed = $line.Trim()

        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

        if ($trimmed -match '^Match\s+') {
            $currentMatch = $trimmed
            continue
        }

        if ($trimmed -match '^(\S+)\s+(.+)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()

            if ($config.ContainsKey($key)) {
                $existing = $config[$key]
                if ($existing -is [array]) {
                    $config[$key] = $existing + $value
                }
                else {
                    $config[$key] = @($existing, $value)
                }
            }
            else {
                $config[$key] = $value
            }
        }
    }

    [pscustomobject]@{
        Config   = $config
        RawLines = $rawLines
        Path     = $Path
        Exists   = $true
    }
}
