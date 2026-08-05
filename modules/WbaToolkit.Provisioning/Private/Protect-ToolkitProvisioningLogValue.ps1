function Protect-ToolkitProvisioningLogValue {
    <#
    .SYNOPSIS
        Redige valores sensiveis antes de qualquer escrita em log, estado ou relatorio.

    .DESCRIPTION
        Percorre uma estrutura (hashtable, PSCustomObject ou string) e substitui por
        '***REDACTED***' qualquer valor cuja chave case com um padrao sensivel
        (senha, secretRef, token, chave, thumbprint de chave privada, etc.) ou cujo
        proprio valor pareca uma SecureString/PSCredential serializada. Nunca lanca
        excecao — falha ao sanitizar deve resultar em texto genérico, nunca no dado bruto.

    .PARAMETER InputObject
        Valor a sanitizar. Aceita string, hashtable ou PSCustomObject.

    .OUTPUTS
        Mesmo tipo de entrada, com valores sensiveis substituidos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $InputObject
    )

    begin {
        $sensitiveKeyPattern = '(?i)(password|senha|secret|token|privatekey|chaveprivada|productkey|pfxpassword|passphrase)'
        $redacted = '***REDACTED***'
    }

    process {
        if ($null -eq $InputObject) {
            return $InputObject
        }

        if ($InputObject -is [System.Security.SecureString] -or $InputObject -is [pscredential]) {
            return $redacted
        }

        if ($InputObject -is [string]) {
            return $InputObject
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $clone = [ordered]@{}
            foreach ($key in $InputObject.Keys) {
                if ($key -match $sensitiveKeyPattern) {
                    $clone[$key] = $redacted
                }
                else {
                    $clone[$key] = Protect-ToolkitProvisioningLogValue -InputObject $InputObject[$key]
                }
            }
            return [pscustomobject]$clone
        }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $clone = [ordered]@{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                if ($prop.Name -match $sensitiveKeyPattern) {
                    $clone[$prop.Name] = $redacted
                }
                else {
                    $clone[$prop.Name] = Protect-ToolkitProvisioningLogValue -InputObject $prop.Value
                }
            }
            return [pscustomobject]$clone
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            return @($InputObject | ForEach-Object { Protect-ToolkitProvisioningLogValue -InputObject $_ })
        }

        return $InputObject
    }
}
