function Test-ToolkitPreflightDesiredState {
    <#
    .SYNOPSIS
        Etapa preflight.system — valida pre-condicoes minimas antes de qualquer alteracao.

    .DESCRIPTION
        Etapa de avaliacao pura: nunca retorna 'Changed', apenas 'Compliant' ou 'Failed'.
        Cobre, na Fase 1, os pre-voos mecanicos e baratos de SPEC-PROVISIONING-STEPS:
        privilegio administrativo e espaco livre para estado/logs. Verificacoes que
        dependem de recursos ainda nao implementados (unicidade de adaptadores/discos,
        disponibilidade de provedores de segredo) entram junto das etapas que os
        introduzirem (Fases 2 e 3).

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State; nao utilizado por esta etapa
        alem da assinatura comum.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status ('Compliant'|'Failed'), Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $failures = New-Object System.Collections.Generic.List[string]

    if (-not (Test-IsAdministrator)) {
        $failures.Add('Processo nao esta em contexto administrativo.')
    }

    if ($PSVersionTable.PSVersion -lt [version]'5.1') {
        $failures.Add("Versao do PowerShell insuficiente: $($PSVersionTable.PSVersion) (minimo 5.1).")
    }

    $systemDrive = $env:SystemDrive
    $freeBytes = $null
    $volume = @(Get-CimInstanceSafe -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'") | Select-Object -First 1
    if ($volume) {
        $freeBytes = [int64]$volume.FreeSpace
        $minimumFreeBytes = 500MB
        if ($freeBytes -lt $minimumFreeBytes) {
            $failures.Add("Espaco livre insuficiente em $systemDrive`: $([math]::Round($freeBytes / 1MB, 0)) MB (minimo $([math]::Round($minimumFreeBytes / 1MB, 0)) MB).")
        }
    }

    $evidence = [pscustomobject]@{
        IsAdministrator = (Test-IsAdministrator)
        PSVersion       = $PSVersionTable.PSVersion.ToString()
        SystemDrive     = $systemDrive
        FreeBytes       = $freeBytes
    }

    if ($failures.Count -gt 0) {
        return [pscustomobject]@{ Status = 'Failed'; Message = ($failures -join ' '); Evidence = $evidence }
    }

    return [pscustomobject]@{ Status = 'Compliant'; Message = 'Pre-voo aprovado.'; Evidence = $evidence }
}
