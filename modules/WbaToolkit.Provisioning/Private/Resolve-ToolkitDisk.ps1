function Resolve-ToolkitDisk {
    <#
    .SYNOPSIS
        Resolve exatamente um disco a partir de um identificador forte, excluindo o disco
        de sistema por padrao.

    .DESCRIPTION
        SPEC-PROVISIONING-CONFIG: o plano exige pelo menos um identificador forte —
        serial, unique ID, ou combinacao de barramento, localizacao e tamanho com
        tolerancia. Indice de disco nunca e usado. Zero ou multiplos candidatos e falha
        explicita; o disco de sistema/boot e excluido mesmo que o criterio o alcance
        (defesa em profundidade), conforme SPEC-PROVISIONING-SECURITY.

    .PARAMETER Match
        Objeto com serialNumber, ou uniqueId, ou (busType + location + sizeBytes
        [+ sizeToleranceBytes]).

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Found, Disk, Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Match
    )

    $allDisks = @(Get-Disk -ErrorAction Stop)
    $candidates = @()
    $criterion = ''

    if ((Test-ToolkitPropertyPresent -InputObject $Match -Name 'serialNumber') -and -not [string]::IsNullOrWhiteSpace([string]$Match.serialNumber)) {
        $criterion = "serialNumber='$($Match.serialNumber)'"
        $candidates = @($allDisks | Where-Object { $_.SerialNumber -and $_.SerialNumber.Trim() -eq $Match.serialNumber.Trim() })
    }
    elseif ((Test-ToolkitPropertyPresent -InputObject $Match -Name 'uniqueId') -and -not [string]::IsNullOrWhiteSpace([string]$Match.uniqueId)) {
        $criterion = "uniqueId='$($Match.uniqueId)'"
        $candidates = @($allDisks | Where-Object { $_.UniqueId -eq [string]$Match.uniqueId })
    }
    elseif ((Test-ToolkitPropertyPresent -InputObject $Match -Name 'busType') -and
        (Test-ToolkitPropertyPresent -InputObject $Match -Name 'location') -and
        (Test-ToolkitPropertyPresent -InputObject $Match -Name 'sizeBytes')) {
        $tolerance = if (Test-ToolkitPropertyPresent -InputObject $Match -Name 'sizeToleranceBytes') { [int64]$Match.sizeToleranceBytes } else { 10MB }
        $criterion = "busType='$($Match.busType)' location='$($Match.location)' sizeBytes~$($Match.sizeBytes)"
        $candidates = @($allDisks | Where-Object {
                $_.BusType -eq [string]$Match.busType -and
                $_.Location -eq [string]$Match.location -and
                [math]::Abs([int64]$_.Size - [int64]$Match.sizeBytes) -le $tolerance
            })
    }
    else {
        return [pscustomobject]@{ Found = $false; Disk = $null; Message = 'Identificador forte ausente (esperado serialNumber, uniqueId, ou busType+location+sizeBytes).' }
    }

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Disk = $null; Message = "Nenhum disco encontrado para $criterion." }
    }

    if ($candidates.Count -gt 1) {
        return [pscustomobject]@{ Found = $false; Disk = $null; Message = "Identificacao ambigua: $($candidates.Count) discos casam com $criterion." }
    }

    $disk = $candidates[0]
    if ($disk.IsSystem -or $disk.IsBoot) {
        return [pscustomobject]@{ Found = $false; Disk = $null; Message = "Disco resolvido para $criterion e o disco de sistema/boot; recusado por seguranca." }
    }

    return [pscustomobject]@{ Found = $true; Disk = $disk; Message = "Disco resolvido por $criterion." }
}
