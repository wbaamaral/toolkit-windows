function Get-ToolkitProvisioningSecretRef {
    <#
    .SYNOPSIS
        Lista os secretRef declarados na configuracao (envelopes consumidos pelo deployment).

    .DESCRIPTION
        Percorre a configuracao recursivamente e coleta valores string de propriedades chamadas
        'secretRef' (ex.: password.secretRef) ou terminadas em 'SecretRef'
        (ex.: activation.productKeySecretRef, source.pfxPasswordSecretRef). Usado por
        cleanup.finalize para remover <Paths.Secrets>\<secretRef>.cms, conforme
        SPEC-PROVISIONING-SECURITY ("Politica de limpeza deve remover envelopes consumidos").

        Valores fora do formato aceito por Resolve-ToolkitProvisioningSecret sao descartados,
        o que impede que um secretRef como '..\x' aponte para fora da pasta de segredos.

    .PARAMETER InputObject
        No atual da arvore de configuracao.

    .OUTPUTS
        System.String[] — secretRef distintos.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        $InputObject
    )

    $found = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.Stack[object]
    if ($null -ne $InputObject) { $pending.Push($InputObject) }

    while ($pending.Count -gt 0) {
        $node = $pending.Pop()
        if ($node -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $node.PSObject.Properties) {
                if ($prop.Value -is [string]) {
                    # -match e case-insensitive: cobre 'secretRef' e '*SecretRef'.
                    if ($prop.Name -match 'secretRef$' -and
                        $prop.Value -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -and
                        -not $found.Contains($prop.Value)) {
                        $found.Add($prop.Value)
                    }
                }
                elseif ($null -ne $prop.Value) {
                    $pending.Push($prop.Value)
                }
            }
        }
        elseif ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
            foreach ($item in $node) {
                if ($null -ne $item) { $pending.Push($item) }
            }
        }
    }

    # Sem a virgula unaria: o chamador usa @() e um array aninhado distorceria a contagem.
    $found.ToArray()
}
