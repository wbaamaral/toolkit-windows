function Resolve-ToolkitNetworkAdapter {
    <#
    .SYNOPSIS
        Resolve exatamente um adaptador de rede a partir de um criterio de identificacao.

    .DESCRIPTION
        SPEC-PROVISIONING-CONFIG: prioridade MAC normalizado, PnP device ID ou alias
        explicitamente declarado. Indice de interface nao e identificador persistente e
        nunca e usado aqui. Zero ou multiplos candidatos e falha explicita — a etapa nao
        deve prosseguir com identificacao ambigua.

    .PARAMETER Match
        Objeto com no maximo um de: macAddress, pnpDeviceId, alias.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Found, Adapter, Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Match
    )

    $allAdapters = @(Get-NetAdapter -ErrorAction Stop)
    $candidates = @()
    $criterion = ''

    if ((Test-ToolkitPropertyPresent -InputObject $Match -Name 'macAddress') -and -not [string]::IsNullOrWhiteSpace([string]$Match.macAddress)) {
        $criterion = "macAddress='$($Match.macAddress)'"
        $desiredMac = ConvertTo-ToolkitNormalizedMacAddress -MacAddress ([string]$Match.macAddress)
        $candidates = @($allAdapters | Where-Object { (ConvertTo-ToolkitNormalizedMacAddress -MacAddress $_.MacAddress) -eq $desiredMac })
    }
    elseif ((Test-ToolkitPropertyPresent -InputObject $Match -Name 'pnpDeviceId') -and -not [string]::IsNullOrWhiteSpace([string]$Match.pnpDeviceId)) {
        $criterion = "pnpDeviceId='$($Match.pnpDeviceId)'"
        $candidates = @($allAdapters | Where-Object { $_.PnPDeviceID -eq [string]$Match.pnpDeviceId })
    }
    elseif ((Test-ToolkitPropertyPresent -InputObject $Match -Name 'alias') -and -not [string]::IsNullOrWhiteSpace([string]$Match.alias)) {
        $criterion = "alias='$($Match.alias)'"
        $candidates = @($allAdapters | Where-Object { $_.Name -eq [string]$Match.alias })
    }
    else {
        return [pscustomobject]@{ Found = $false; Adapter = $null; Message = "Criterio de identificacao de adaptador ausente ou vazio (esperado macAddress, pnpDeviceId ou alias)." }
    }

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Adapter = $null; Message = "Nenhum adaptador encontrado para $criterion." }
    }

    if ($candidates.Count -gt 1) {
        return [pscustomobject]@{ Found = $false; Adapter = $null; Message = "Identificacao ambigua: $($candidates.Count) adaptadores casam com $criterion." }
    }

    return [pscustomobject]@{ Found = $true; Adapter = $candidates[0]; Message = "Adaptador resolvido por $criterion." }
}
