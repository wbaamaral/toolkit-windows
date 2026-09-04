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

    # Mock para lab Docker/Linux (WBA_MOCK_AD) — permite testar diagnóstico AD sem binários Windows
    if ($env:WBA_MOCK_AD -and $FilePath -match '^(w32tm|nltest|gpresult|wevtutil|powercfg|dxdiag)(\.exe)?$') {
        $joined = ($ArgumentList -join ' ').ToLowerInvariant()
        if ($FilePath -match 'w32tm' -and $joined -match '/query.*\/source') {
            return [PSCustomObject]@{ ExitCode = 0; Output = '172.20.0.10 (mock WBA_MOCK_AD)' }
        }
        if ($FilePath -match 'w32tm' -and $joined -match '/query.*\/status') {
            return [PSCustomObject]@{ ExitCode = 0; Output = 'Stratum: 3 (mock)' }
        }
        if ($FilePath -match 'nltest') {
            return [PSCustomObject]@{ ExitCode = 0; Output = "DC: \\dc01.wba.test`n" }
        }
        if ($FilePath -match 'gpresult') {
            return [PSCustomObject]@{ ExitCode = 0; Output = 'Mock gpresult' }
        }
        return [PSCustomObject]@{ ExitCode = 0; Output = '' }
    }

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
