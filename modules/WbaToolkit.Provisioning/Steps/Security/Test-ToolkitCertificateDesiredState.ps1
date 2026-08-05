function Test-ToolkitCertificateDesiredState {
    <#
    .SYNOPSIS
        Etapa certificates.install — verifica se os certificados declarados estao instalados.

    .DESCRIPTION
        Cada entrada de computer.certificates declara o thumbprint esperado apos a instalacao
        (identidade do certificado, nunca a chave privada). Compliant quando o thumbprint ja
        existe no repositorio declarado; caso contrario, Changed. Nao ha estado 'Failed' aqui
        — origem invalida so se manifesta durante Set (tratado la, sanitizado pelo executor).

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status, Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $config = $Context.Config
    if (-not ($config -and (Test-ToolkitPropertyPresent -InputObject $config -Name 'certificates'))) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'certificates' nao declarada."; Evidence = $null }
    }

    $entries = @($config.certificates)
    if ($entries.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "'certificates' esta vazio."; Evidence = $null }
    }

    $evaluations = @()
    foreach ($entry in $entries) {
        $store = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'store') -and $entry.store) { [string]$entry.store } else { 'LocalMachine\My' }
        $found = Find-ToolkitProvisioningCertificate -Thumbprint ([string]$entry.thumbprint) -Store $store
        $evaluations += [pscustomobject]@{ Name = $entry.name; Thumbprint = $entry.thumbprint; Store = $store; IsCompliant = [bool]$found }
    }

    $missing = @($evaluations | Where-Object { -not $_.IsCompliant })
    $evidence = [pscustomobject]@{ Certificates = $evaluations }

    if ($missing.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'Todos os certificados declarados ja estao instalados.'; Evidence = $evidence }
    }

    $names = ($missing | ForEach-Object { $_.Name }) -join ', '
    return [pscustomobject]@{ Status = 'Changed'; Message = "Certificados pendentes de instalacao: $names."; Evidence = $evidence }
}
