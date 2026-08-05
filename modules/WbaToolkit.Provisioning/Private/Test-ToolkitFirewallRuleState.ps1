function Test-ToolkitFirewallRuleState {
    <#
    .SYNOPSIS
        Compara uma regra de firewall nomeada com as propriedades desejadas.

    .DESCRIPTION
        Identifica a regra por 'Name' (identificador interno estavel), nunca por
        'DisplayName'/'DisplayGroup' (localizados por idioma do Windows). Sem efeitos
        colaterais. Usada por remoteaccess.winrm e firewall.rules.

    .PARAMETER Name
        Nome interno da regra (CimInstance Name, nao o rotulo exibido).

    .PARAMETER Enabled
    .PARAMETER Direction
        Inbound | Outbound. Padrao: Inbound.
    .PARAMETER Protocol
        TCP | UDP | Any.
    .PARAMETER LocalPort
    .PARAMETER Profile
        Array de perfis: Domain, Private, Public.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — IsCompliant, Exists, Details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Enabled,

        [string]$Direction = 'Inbound',
        [string]$Protocol,
        [string]$LocalPort,
        [string[]]$Profile
    )

    $rule = Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue
    if (-not $rule) {
        return [pscustomobject]@{
            IsCompliant = (-not $Enabled)
            Exists      = $false
            Details     = [pscustomobject]@{ Name = $Name; Reason = 'Regra nao existe.' }
        }
    }

    if (-not $Enabled) {
        return [pscustomobject]@{
            IsCompliant = ($rule.Enabled -eq $false)
            Exists      = $true
            Details     = [pscustomobject]@{ Name = $Name; CurrentEnabled = $rule.Enabled }
        }
    }

    # O objeto de Get-NetFirewallRule ja expoe o perfil diretamente em .Profile (string
    # com flags separadas por virgula, ex. 'Domain, Private'); nao ha necessidade de
    # consultar Get-NetFirewallProfile (que reporta as PROPRIAS definicoes de perfil,
    # nao a associacao de uma regra).
    $currentProfileNames = @([string]$rule.Profile -split ',\s*' | Where-Object { $_ })
    $desiredProfileSorted = @($Profile | Sort-Object)
    $currentProfileSorted = @($currentProfileNames | Sort-Object)

    $portMatches = $true
    if ($Protocol) {
        $filter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
        if ($filter) {
            $portMatches = ($filter.Protocol -eq $Protocol) -and (-not $LocalPort -or $filter.LocalPort -eq $LocalPort)
        }
    }

    $isCompliant = ($rule.Enabled -eq $true) -and $portMatches -and
        (@(Compare-Object $currentProfileSorted $desiredProfileSorted).Count -eq 0)

    [pscustomobject]@{
        IsCompliant = [bool]$isCompliant
        Exists      = $true
        Details     = [pscustomobject]@{
            Name             = $Name
            CurrentEnabled   = $rule.Enabled
            CurrentProfile   = $currentProfileSorted
            DesiredProfile   = $desiredProfileSorted
            PortMatches      = $portMatches
        }
    }
}
