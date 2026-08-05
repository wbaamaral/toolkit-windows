function Test-ToolkitProvisioningSchema {
    <#
    .SYNOPSIS
        Valida estrutura e semantica basica de uma configuracao de provisionamento v1.

    .DESCRIPTION
        Implementa SPEC-PROVISIONING-CONFIG: schemaVersion e deploymentId obrigatorios,
        campos desconhecidos no nivel raiz falham por padrao, valores secretos so podem
        aparecer como { "secretRef": "..." }, e a secao 'computer' (unica implementada na
        Fase 1) e validada em detalhe. Nunca altera o sistema.

    .PARAMETER Config
        Objeto de configuracao ja convertido de JSON (ConvertFrom-Json).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: IsValid, Errors (string[]), Warnings (string[]).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Config
    )

    $errors   = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    $supportedSchemaVersions = @(1)
    $knownRootKeys = @(
        '$schema', 'schemaVersion', 'deploymentId', 'computer', 'network', 'storage',
        'certificates', 'remoteAccess', 'firewall', 'accounts', 'activation', 'sysprep',
        'extensions', 'policy'
    )
    $knownPolicyKeys      = @('onError', 'maxAttemptsPerStep', 'reboot', 'cleanup')
    $validOnError         = @('Stop', 'Continue')
    $validReboot          = @('Never', 'WhenRequired', 'Manual')
    $validCleanup         = @('RemoveSecretsAndConfig', 'RemoveSecretsOnly', 'RetainAll')

    if ($null -eq $Config) {
        $errors.Add('Configuracao vazia ou nao convertida.')
        return [pscustomobject]@{ IsValid = $false; Errors = @($errors); Warnings = @($warnings) }
    }

    $rootProps = @($Config.PSObject.Properties.Name)
    foreach ($key in $rootProps) {
        if ($knownRootKeys -notcontains $key) {
            $errors.Add("Campo desconhecido no nivel raiz: '$key'.")
        }
    }

    if (-not ($rootProps -contains 'schemaVersion') -or [string]::IsNullOrEmpty([string]$Config.schemaVersion)) {
        $errors.Add("Campo obrigatorio ausente: 'schemaVersion'.")
    }
    elseif ($supportedSchemaVersions -notcontains [int]$Config.schemaVersion) {
        $errors.Add("schemaVersion '$($Config.schemaVersion)' nao e suportada por este modulo (suportadas: $($supportedSchemaVersions -join ', ')).")
    }

    if (-not ($rootProps -contains 'deploymentId') -or [string]::IsNullOrWhiteSpace([string]$Config.deploymentId)) {
        $errors.Add("Campo obrigatorio ausente ou vazio: 'deploymentId'.")
    }
    elseif ([string]$Config.deploymentId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        $errors.Add("'deploymentId' contem caracteres invalidos ou excede 128 caracteres: '$($Config.deploymentId)'.")
    }

    if ($rootProps -contains 'computer') {
        $computerProps = @($Config.computer.PSObject.Properties.Name)
        $knownComputerKeys = @('name', 'timeZone')
        foreach ($key in $computerProps) {
            if ($knownComputerKeys -notcontains $key) {
                $errors.Add("Campo desconhecido em 'computer': '$key'.")
            }
        }
        if ($computerProps -contains 'name' -and [string]$Config.computer.name -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
            $errors.Add("'computer.name' invalido para NetBIOS (1-15 caracteres alfanumericos/hifen): '$($Config.computer.name)'.")
        }
        if ($computerProps -contains 'timeZone' -and [string]::IsNullOrWhiteSpace([string]$Config.computer.timeZone)) {
            $errors.Add("'computer.timeZone' nao pode ser vazio quando declarado.")
        }
    }

    if ($rootProps -contains 'policy') {
        $policyProps = @($Config.policy.PSObject.Properties.Name)
        foreach ($key in $policyProps) {
            if ($knownPolicyKeys -notcontains $key) {
                $errors.Add("Campo desconhecido em 'policy': '$key'.")
            }
        }
        if ($policyProps -contains 'onError' -and $validOnError -notcontains [string]$Config.policy.onError) {
            $errors.Add("'policy.onError' invalido: '$($Config.policy.onError)' (valores aceitos: $($validOnError -join ', ')).")
        }
        if ($policyProps -contains 'reboot' -and $validReboot -notcontains [string]$Config.policy.reboot) {
            $errors.Add("'policy.reboot' invalido: '$($Config.policy.reboot)' (valores aceitos: $($validReboot -join ', ')).")
        }
        if ($policyProps -contains 'cleanup' -and $validCleanup -notcontains [string]$Config.policy.cleanup) {
            $errors.Add("'policy.cleanup' invalido: '$($Config.policy.cleanup)' (valores aceitos: $($validCleanup -join ', ')).")
        }
        if ($policyProps -contains 'maxAttemptsPerStep') {
            $maxAttempts = 0
            if (-not [int]::TryParse([string]$Config.policy.maxAttemptsPerStep, [ref]$maxAttempts) -or $maxAttempts -lt 1) {
                $errors.Add("'policy.maxAttemptsPerStep' deve ser um inteiro maior ou igual a 1.")
            }
        }
    }
    else {
        $warnings.Add("Secao 'policy' ausente; assumindo padroes (onError=Stop, reboot=WhenRequired, maxAttemptsPerStep=3).")
    }

    foreach ($section in @('network', 'storage', 'certificates', 'remoteAccess', 'firewall', 'accounts', 'activation', 'extensions')) {
        if ($rootProps -contains $section) {
            $warnings.Add("Secao '$section' presente, mas nenhuma etapa da Fase 1 a consome ainda; sera ignorada nesta execucao.")
        }
    }

    $plaintextSecretKeyPattern = '(?i)^(password|senha|productkey|token|privatekey|passphrase)$'
    $plaintextFindings = @(Find-ToolkitProvisioningPlaintextSecret -InputObject $Config -KeyPattern $plaintextSecretKeyPattern)
    foreach ($finding in $plaintextFindings) {
        $errors.Add("Valor secreto em texto claro detectado em '$finding'; use { `"secretRef`": `"...`" }.")
    }

    [pscustomobject]@{
        IsValid  = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}
