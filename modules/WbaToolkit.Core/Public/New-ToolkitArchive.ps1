function New-ToolkitArchive {
    <#
    .SYNOPSIS
        Cria pacote ZIP a partir de um diretorio e opcionalmente gera hash SHA256.

    .DESCRIPTION
        Funcao reutilizavel para empacotar arquivos em ZIP com integridade verificavel.
        Suporta geracao automatica de hash SHA256 e nomeacao com versao.

    .PARAMETER SourcePath
        Diretorio ou arquivo a ser empacotado.

    .PARAMETER DestinationPath
        Caminho completo do arquivo ZIP de saida (incluindo extensao .zip).

    .PARAMETER GenerateHash
        Se $true, gera arquivo .sha256sum junto com o ZIP.

    .PARAMETER Quiet
        Se $true, nao exibe mensagens de progresso.

    .OUTPUTS
        PSCustomObject com ZipPath, Hash e HashPath.

    .EXAMPLE
        $result = New-ToolkitArchive -SourcePath "C:\drivers" -DestinationPath "C:\backup\drv_pc01.zip" -GenerateHash

    .EXAMPLE
        $result = New-ToolkitArchive -SourcePath "C:\drivers" -DestinationPath "C:\backup\drv_pc01.zip" -GenerateHash -Quiet
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [switch]$GenerateHash,

        [switch]$Quiet
    )

    # Validar origem
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Caminho de origem nao encontrado: $SourcePath"
    }

    # Criar diretorio de destino se nao existir
    $destDir = Split-Path -Parent $DestinationPath
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    # Remover ZIP existente
    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }

    # Criar ZIP
    if (-not $Quiet) {
        Write-Verbose "Empacotando: $SourcePath -> $DestinationPath"
    }

    Compress-Archive -Path "$SourcePath\*" -DestinationPath $DestinationPath -Force -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw "Falha ao criar arquivo ZIP: $DestinationPath"
    }

    $zipSize = [math]::Round((Get-Item -LiteralPath $DestinationPath).Length / 1KB, 1)
    if (-not $Quiet) {
        Write-Verbose "ZIP criado: $DestinationPath ($zipSize KB)"
    }

    # Gerar hash se solicitado
    $hash = $null
    $hashPath = $null
    if ($GenerateHash) {
        $hash = Get-FileHashSha256 -Path $DestinationPath -Quiet
        $hashPath = "$DestinationPath.sha256sum"
        Get-FileHashSha256 -Path $DestinationPath -SaveToFile -Quiet
        if (-not $Quiet) {
            Write-Verbose "Hash SHA256: $hash"
        }
    }

    return [pscustomobject]@{
        ZipPath  = $DestinationPath
        ZipSize  = $zipSize
        Hash     = $hash
        HashPath = $hashPath
    }
}
