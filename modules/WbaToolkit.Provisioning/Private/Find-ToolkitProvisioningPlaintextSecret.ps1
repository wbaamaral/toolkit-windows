function Find-ToolkitProvisioningPlaintextSecret {
    <#
    .SYNOPSIS
        Percorre recursivamente a configuracao em busca de segredo em texto claro.

    .DESCRIPTION
        Uma propriedade cujo nome case com $KeyPattern (senha, chave de produto, token,
        etc.) so e aceita quando seu valor e um objeto com a propriedade 'secretRef'.
        Qualquer outro tipo de valor (string, numero) e reportado como violacao,
        conforme regra 1 de SPEC-PROVISIONING-SECURITY.

    .PARAMETER InputObject
        No atual da arvore de configuracao.

    .PARAMETER KeyPattern
        Expressao regular que identifica nomes de campo sensiveis.

    .PARAMETER Path
        Caminho pontilhado acumulado, usado apenas para reportar o local do achado.

    .OUTPUTS
        System.String[] — caminhos pontilhados dos campos violadores.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$KeyPattern,

        [string]$Path = '$'
    )

    $findings = New-Object System.Collections.Generic.List[string]

    if ($null -eq $InputObject) {
        return @($findings)
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $InputObject.PSObject.Properties) {
            $childPath = "$Path.$($prop.Name)"
            if ($prop.Name -match $KeyPattern) {
                $isSecretRefEnvelope = ($prop.Value -is [System.Management.Automation.PSCustomObject]) -and
                    ($prop.Value.PSObject.Properties.Name -contains 'secretRef')
                if (-not $isSecretRefEnvelope) {
                    $findings.Add($childPath)
                    continue
                }
            }
            $findings.AddRange([string[]]@(Find-ToolkitProvisioningPlaintextSecret -InputObject $prop.Value -KeyPattern $KeyPattern -Path $childPath))
        }
    }
    elseif ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $index = 0
        foreach ($item in $InputObject) {
            $findings.AddRange([string[]]@(Find-ToolkitProvisioningPlaintextSecret -InputObject $item -KeyPattern $KeyPattern -Path "$Path[$index]"))
            $index++
        }
    }

    return @($findings)
}
