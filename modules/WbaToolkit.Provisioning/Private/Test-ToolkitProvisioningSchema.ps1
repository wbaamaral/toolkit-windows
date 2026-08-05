function Test-ToolkitProvisioningSchema {
    <#
    .SYNOPSIS
        Valida estrutura e semantica basica de uma configuracao de provisionamento v1.

    .DESCRIPTION
        Implementa SPEC-PROVISIONING-CONFIG: schemaVersion e deploymentId obrigatorios,
        campos desconhecidos no nivel raiz falham por padrao, valores secretos so podem
        aparecer como { "secretRef": "..." }. As secoes com etapa implementada (computer,
        network, certificates, remoteAccess, firewall) sao validadas em detalhe; as demais
        (storage, accounts, activation, extensions) apenas emitem aviso. Nunca altera o
        sistema.

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

    $rootProps = (Get-ToolkitPropertyNames -InputObject $Config)
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
        $computerProps = (Get-ToolkitPropertyNames -InputObject $Config.computer)
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
        $policyProps = (Get-ToolkitPropertyNames -InputObject $Config.policy)
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

    $validProfiles = @('Domain', 'Private', 'Public')

    if ($rootProps -contains 'network') {
        $networkProps = (Get-ToolkitPropertyNames -InputObject $Config.network)
        if ($networkProps -notcontains 'adapters') {
            $errors.Add("Secao 'network' presente sem 'adapters'.")
        }
        else {
            foreach ($adapter in @($Config.network.adapters)) {
                $adapterProps = (Get-ToolkitPropertyNames -InputObject $adapter)
                $matchProps = if ($adapterProps -contains 'match') { (Get-ToolkitPropertyNames -InputObject $adapter.match) } else { @() }
                $matchKeys = @($matchProps | Where-Object { $_ -in @('macAddress', 'pnpDeviceId', 'alias') -and -not [string]::IsNullOrWhiteSpace([string]$adapter.match.$_) })
                if ($matchKeys.Count -ne 1) {
                    $errors.Add("Adaptador '$($adapter.name)': 'match' deve ter exatamente um de macAddress, pnpDeviceId ou alias.")
                }
                if ($adapterProps -notcontains 'name' -or [string]::IsNullOrWhiteSpace([string]$adapter.name)) {
                    $errors.Add("Adaptador sem 'name' declarado.")
                }
                if ($adapterProps -notcontains 'dhcp') {
                    $errors.Add("Adaptador '$($adapter.name)': campo 'dhcp' obrigatorio.")
                }
                elseif (-not [bool]$adapter.dhcp) {
                    if ($adapterProps -notcontains 'addresses' -or @($adapter.addresses).Count -eq 0) {
                        $errors.Add("Adaptador '$($adapter.name)': 'addresses' obrigatorio quando dhcp=false.")
                    }
                    else {
                        foreach ($cidr in @($adapter.addresses)) {
                            if ([string]$cidr -notmatch '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$') {
                                $errors.Add("Adaptador '$($adapter.name)': endereco invalido (esperado CIDR): '$cidr'.")
                            }
                        }
                    }
                    if ($adapterProps -contains 'gateway' -and [string]$adapter.gateway -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
                        $errors.Add("Adaptador '$($adapter.name)': 'gateway' invalido: '$($adapter.gateway)'.")
                    }
                }
            }
        }
    }

    if ($rootProps -contains 'certificates') {
        foreach ($cert in @($Config.certificates)) {
            $certProps = (Get-ToolkitPropertyNames -InputObject $cert)
            if ($certProps -notcontains 'thumbprint' -or [string]$cert.thumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
                $errors.Add("Certificado '$($cert.name)': 'thumbprint' ausente ou invalido (esperado 40 caracteres hexadecimais).")
            }
            $sourceProps = if ($certProps -contains 'source') { (Get-ToolkitPropertyNames -InputObject $cert.source) } else { @() }
            $sourceKeys = @($sourceProps | Where-Object { $_ -in @('filePath', 'contentBase64') -and -not [string]::IsNullOrWhiteSpace([string]$cert.source.$_) })
            if ($sourceKeys.Count -ne 1) {
                $errors.Add("Certificado '$($cert.name)': 'source' deve ter exatamente um de filePath ou contentBase64.")
            }
        }
    }

    if ($rootProps -contains 'remoteAccess') {
        foreach ($feature in @('winrm', 'rdp')) {
            if ((Get-ToolkitPropertyNames -InputObject $Config.remoteAccess) -notcontains $feature) {
                continue
            }
            $featureConfig = $Config.remoteAccess.$feature
            $featureProps = (Get-ToolkitPropertyNames -InputObject $featureConfig)
            if ($featureProps -contains 'firewallProfile') {
                foreach ($p in @($featureConfig.firewallProfile)) {
                    if ($validProfiles -notcontains [string]$p) {
                        $errors.Add("remoteAccess.$feature.firewallProfile invalido: '$p' (aceitos: $($validProfiles -join ', ')).")
                    }
                }
            }
            if ($feature -eq 'winrm' -and $featureProps -contains 'enabled' -and $featureConfig.enabled) {
                if ($featureProps -notcontains 'certificateThumbprint' -or [string]$featureConfig.certificateThumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
                    $errors.Add("remoteAccess.winrm.enabled=true exige 'certificateThumbprint' valido (40 caracteres hexadecimais).")
                }
            }
        }
    }

    if ($rootProps -contains 'firewall') {
        $firewallProps = (Get-ToolkitPropertyNames -InputObject $Config.firewall)
        if ($firewallProps -contains 'rules') {
            foreach ($rule in @($Config.firewall.rules)) {
                $ruleProps = (Get-ToolkitPropertyNames -InputObject $rule)
                if ($ruleProps -notcontains 'name' -or [string]::IsNullOrWhiteSpace([string]$rule.name)) {
                    $errors.Add("Regra de firewall sem 'name' declarado.")
                }
                if ($ruleProps -contains 'direction' -and @('Inbound', 'Outbound') -notcontains [string]$rule.direction) {
                    $errors.Add("Regra '$($rule.name)': 'direction' invalido: '$($rule.direction)'.")
                }
                if ($ruleProps -contains 'protocol' -and @('TCP', 'UDP', 'Any') -notcontains [string]$rule.protocol) {
                    $errors.Add("Regra '$($rule.name)': 'protocol' invalido: '$($rule.protocol)'.")
                }
                if ($ruleProps -contains 'profile') {
                    foreach ($p in @($rule.profile)) {
                        if ($validProfiles -notcontains [string]$p) {
                            $errors.Add("Regra '$($rule.name)': profile invalido: '$p' (aceitos: $($validProfiles -join ', ')).")
                        }
                    }
                }
            }
        }
    }

    foreach ($section in @('storage', 'accounts', 'activation', 'extensions')) {
        if ($rootProps -contains $section) {
            $warnings.Add("Secao '$section' presente, mas nenhuma etapa implementada a consome ainda; sera ignorada nesta execucao.")
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
