function Invoke-ExternalCommand {
    <#
    .SYNOPSIS
        Executa um comando externo e retorna codigo de saida e saida textual.

    .DESCRIPTION
        Valida se o comando existe, executa o binario informado com argumentos e
        retorna um objeto com ExitCode e Output.

    .PARAMETER FilePath
        Caminho ou nome do executavel a ser chamado.

    .PARAMETER ArgumentList
        Argumentos passados ao executavel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @()
    )

    if (-not (Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{
            ExitCode = 127
            Output   = "Comando não encontrado: $FilePath"
        }
    }

    try {
        $global:LASTEXITCODE = 0
        $output = & $FilePath @ArgumentList 2>&1
        return [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output   = (($output | Out-String).Trim())
        }
    }
    catch {
        return [PSCustomObject]@{
            ExitCode = 1
            Output   = $_.Exception.Message
        }
    }
}
