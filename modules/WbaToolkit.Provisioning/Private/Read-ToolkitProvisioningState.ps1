function Read-ToolkitProvisioningState {
    <#
    .SYNOPSIS
        Le state.json, com fallback para state.previous.json em caso de corrupcao.

    .DESCRIPTION
        SPEC-PROVISIONING-ENGINE: estado invalido na inicializacao nao deve ser ignorado.
        Tenta a copia anterior; se ambas falharem, devolve um marcador de falha explicito
        em vez de lancar silenciosamente — o motor deve transicionar para 'Failed' e
        exigir intervencao, nunca reiniciar do zero por conta propria.

    .PARAMETER StateDirectory
        Diretorio de trabalho do deployment (Work\<deploymentId>).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Found, State, RecoveredFromPrevious, CorruptionDetected.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StateDirectory
    )

    $finalPath    = Join-Path $StateDirectory 'state.json'
    $previousPath = Join-Path $StateDirectory 'state.previous.json'

    $finalExists    = Test-Path -LiteralPath $finalPath -PathType Leaf
    $previousExists = Test-Path -LiteralPath $previousPath -PathType Leaf

    if (-not $finalExists -and -not $previousExists) {
        return [pscustomobject]@{
            Found                 = $false
            State                 = $null
            RecoveredFromPrevious = $false
            CorruptionDetected    = $false
        }
    }

    if ($finalExists) {
        try {
            $state = Get-Content -LiteralPath $finalPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $state) { throw 'arquivo vazio.' }
            return [pscustomobject]@{
                Found                 = $true
                State                 = $state
                RecoveredFromPrevious = $false
                CorruptionDetected    = $false
            }
        }
        catch {
            Write-Warning "state.json corrompido em '$finalPath': $($_.Exception.Message)"
        }
    }
    else {
        # state.json ausente com state.previous.json presente: interrupcao entre a copia de
        # seguranca e a promocao do novo estado. Nao e um deployment novo.
        Write-Warning "state.json ausente em '$StateDirectory'; tentando state.previous.json."
    }

    if ($previousExists) {
        try {
            $state = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $state) { throw 'arquivo vazio.' }
            return [pscustomobject]@{
                Found                 = $true
                State                 = $state
                RecoveredFromPrevious = $true
                CorruptionDetected    = $true
            }
        }
        catch {
            Write-Warning "state.previous.json tambem corrompido em '$previousPath': $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        Found                 = $true
        State                 = $null
        RecoveredFromPrevious = $false
        CorruptionDetected    = $true
    }
}
