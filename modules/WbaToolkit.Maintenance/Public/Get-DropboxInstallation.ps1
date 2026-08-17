# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxInstallation {
    <#
    .SYNOPSIS
        Localiza instalacoes do cliente Dropbox no perfil do usuario atual.

    .DESCRIPTION
        Adaptacao nao-interativa de Get-DropboxPaths do script autonomo original
        (dropbox-arquivos-v1.ps1). Le %APPDATA%\Dropbox\info.json e
        %LOCALAPPDATA%\Dropbox\info.json, que podem listar mais de uma conta/pasta.
        Nunca lanca por ausencia de instalacao -- retorna array vazio. Se um
        info.json existir mas estiver malformado, emite Write-Warning e continua
        com os demais arquivos. Funcao puramente de dados: sem prompts, sem
        Write-Host.

    .EXAMPLE
        Get-DropboxInstallation

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Um objeto por conta/pasta valida encontrada, com Conta, Caminho e InfoJson.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    $infoFiles = @(
        (Join-Path $env:APPDATA 'Dropbox\info.json'),
        (Join-Path $env:LOCALAPPDATA 'Dropbox\info.json')
    ) | Select-Object -Unique

    $found = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($infoFile in $infoFiles) {
        if (-not (Test-Path -LiteralPath $infoFile -PathType Leaf)) {
            continue
        }

        try {
            $json = Get-Content -LiteralPath $infoFile -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            Write-Warning "Nao foi possivel interpretar '$infoFile': $($_.Exception.Message)"
            continue
        }

        foreach ($property in $json.PSObject.Properties) {
            $accountName = $property.Name
            $accountData = $property.Value

            if ($null -eq $accountData) {
                continue
            }

            if ($null -eq $accountData.PSObject.Properties['path']) {
                continue
            }

            $candidate = [string]$accountData.path
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }

            $candidate = [Environment]::ExpandEnvironmentVariables($candidate)

            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $resolved = (Resolve-Path -LiteralPath $candidate).Path
                $found.Add([pscustomobject]@{
                    Conta    = $accountName
                    Caminho  = $resolved
                    InfoJson = $infoFile
                })
            }
        }
    }

    return @($found | Sort-Object Caminho -Unique)
}
