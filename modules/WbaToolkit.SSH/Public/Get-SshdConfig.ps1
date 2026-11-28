function Get-SshdConfig {
    <#
    .SYNOPSIS
        Le e retorna o sshd_config como hashtable estruturado.

    .DESCRIPTION
        Parseia o arquivo sshd_config e retorna cada diretriz global como par chave-valor.
        Diretivas duplicadas sao retornadas como array. Comentarios e linhas vazias
        sao ignorados. Diretivas dentro de blocos Match valem so para quem atende ao
        criterio, por isso ficam em MatchBlocks e nao entram em Config.

    .PARAMETER Path
        Caminho do sshd_config. Padrao: %programdata%\ssh\sshd_config.

    .OUTPUTS
        PSCustomObject com: Config (hashtable global), MatchBlocks[] (Criteria, Config), RawLines[], Path, Exists.

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
            Config      = @{}
            MatchBlocks = @()
            RawLines    = @()
            Path        = $Path
            Exists      = $false
        }
    }

    $addValue = {
        param([hashtable]$Target, [string]$Key, [string]$Value)
        if ($Target.ContainsKey($Key)) {
            $Target[$Key] = @($Target[$Key]) + $Value
        }
        else {
            $Target[$Key] = $Value
        }
    }

    $rawLines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $config = @{}
    $matchBlocks = [System.Collections.Generic.List[object]]::new()
    $target = $config

    foreach ($line in $rawLines) {
        $trimmed = $line.Trim()

        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

        if ($trimmed -match '^Match\s+(.+)$') {
            $block = [pscustomobject]@{ Criteria = $Matches[1].Trim(); Config = @{} }
            $matchBlocks.Add($block)
            $target = $block.Config
            continue
        }

        if ($trimmed -match '^(\S+)\s+(.+)$') {
            & $addValue $target $Matches[1] $Matches[2].Trim()
        }
    }

    [pscustomobject]@{
        Config      = $config
        MatchBlocks = $matchBlocks.ToArray()
        RawLines    = $rawLines
        Path        = $Path
        Exists      = $true
    }
}