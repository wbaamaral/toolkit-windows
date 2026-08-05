function Write-ToolkitProvisioningState {
    <#
    .SYNOPSIS
        Persiste state.json de forma atomica, com backup da versao anterior.

    .DESCRIPTION
        Implementa a sequencia de SPEC-PROVISIONING-ENGINE: serializa para arquivo
        temporario no mesmo volume, valida a leitura do temporario, preserva o estado
        anterior como 'state.previous.json' e so entao promove o temporario a
        'state.json'. Nenhum reboot ou proxima etapa deve ocorrer antes desta funcao
        retornar com sucesso.

    .PARAMETER StateDirectory
        Diretorio de trabalho do deployment (Work\<deploymentId>).

    .PARAMETER State
        Objeto de estado completo a persistir.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$StateDirectory,

        [Parameter(Mandatory)]
        [pscustomobject]$State
    )

    if (-not (Test-Path -LiteralPath $StateDirectory)) {
        New-Item -Path $StateDirectory -ItemType Directory -Force | Out-Null
    }

    $finalPath    = Join-Path $StateDirectory 'state.json'
    $previousPath = Join-Path $StateDirectory 'state.previous.json'
    $tempPath     = Join-Path $StateDirectory "state.$([guid]::NewGuid().ToString('N')).tmp"

    if (-not $PSCmdlet.ShouldProcess($finalPath, 'Gravar estado de provisionamento')) {
        return
    }

    $json = $State | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))

    try {
        $roundTrip = Get-Content -LiteralPath $tempPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $roundTrip) {
            throw 'Leitura de verificacao do arquivo temporario retornou vazio.'
        }
    }
    catch {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        throw "Falha ao validar o estado gravado antes da promocao: $($_.Exception.Message)"
    }

    if (Test-Path -LiteralPath $finalPath) {
        Copy-Item -LiteralPath $finalPath -Destination $previousPath -Force
    }

    Move-Item -LiteralPath $tempPath -Destination $finalPath -Force
}
