function Resolve-ToolkitProvisioningPlan {
    <#
    .SYNOPSIS
        Calcula a ordem determinística de execucao a partir do grafo de dependencias.

    .DESCRIPTION
        Ordenacao topologica (Kahn) sobre o registro de etapas instaladas
        (SPEC-PROVISIONING-ENGINE). Empates de grau zero sao desempatados por Id
        (ordem alfabetica) para garantir determinismo entre execucoes. Dependencia para
        etapa inexistente no registro ou ciclo no grafo sao erros de validacao.

    .PARAMETER StepRegistry
        Array de manifestos de etapa (Get-ToolkitProvisioningStepRegistry).

    .OUTPUTS
        System.Collections.Hashtable[] — manifestos na ordem de execucao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$StepRegistry
    )

    $byId = @{}
    foreach ($step in $StepRegistry) {
        if ($byId.ContainsKey($step.Id)) {
            throw "Etapa duplicada no registro: '$($step.Id)'."
        }
        $byId[$step.Id] = $step
    }

    foreach ($step in $StepRegistry) {
        foreach ($dependency in @($step.DependsOn)) {
            if (-not $byId.ContainsKey($dependency)) {
                throw "Etapa '$($step.Id)' depende de '$dependency', que nao esta registrada."
            }
        }
    }

    $remainingDeps = @{}
    foreach ($step in $StepRegistry) {
        $remainingDeps[$step.Id] = New-Object System.Collections.Generic.List[string]
        $remainingDeps[$step.Id].AddRange([string[]]@($step.DependsOn))
    }

    $ordered = New-Object System.Collections.Generic.List[hashtable]
    $pendingIds = New-Object System.Collections.Generic.List[string]
    $pendingIds.AddRange([string[]]@($byId.Keys))

    while ($pendingIds.Count -gt 0) {
        $ready = @($pendingIds | Where-Object { $remainingDeps[$_].Count -eq 0 } | Sort-Object)

        if ($ready.Count -eq 0) {
            throw "Ciclo de dependencias detectado entre as etapas: $($pendingIds -join ', ')."
        }

        $currentId = $ready[0]
        $ordered.Add($byId[$currentId])
        $pendingIds.Remove($currentId) | Out-Null

        foreach ($id in $pendingIds) {
            $remainingDeps[$id].Remove($currentId) | Out-Null
        }
    }

    return @($ordered)
}
