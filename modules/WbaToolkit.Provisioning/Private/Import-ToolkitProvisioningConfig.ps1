function Import-ToolkitProvisioningConfig {
    <#
    .SYNOPSIS
        Le um arquivo de configuracao de provisionamento e calcula seu hash SHA-256.

    .DESCRIPTION
        Nao interpreta nem valida semantica; apenas garante que o conteudo e JSON bem
        formado e devolve o objeto convertido junto do hash dos bytes brutos do arquivo,
        exigido por SPEC-PROVISIONING-CONFIG para deteccao de alteracao silenciosa.

    .PARAMETER Path
        Caminho do arquivo JSON de configuracao.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Config (objeto convertido), RawContent, Sha256, Path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo de configuracao nao encontrado: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Configuracao nao e JSON valido ($Path): $($_.Exception.Message)"
    }

    $hash = Get-FileHashSha256 -Path $Path

    [pscustomobject]@{
        Config      = $config
        RawContent  = $raw
        Sha256      = $hash
        Path        = $Path
    }
}
