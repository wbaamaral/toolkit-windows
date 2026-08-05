function Set-ToolkitFirewallRuleState {
    <#
    .SYNOPSIS
        Cria, atualiza, habilita ou desabilita uma regra de firewall nomeada.

    .DESCRIPTION
        Identifica a regra por 'Name' (identificador interno estavel). Nunca desabilita
        o firewall globalmente — apenas gerencia a regra indicada. Usada por
        remoteaccess.winrm e firewall.rules.

    .PARAMETER Name
    .PARAMETER Enabled
    .PARAMETER Direction
    .PARAMETER Protocol
    .PARAMETER LocalPort
    .PARAMETER Profile
    .PARAMETER DisplayName
        Rotulo legivel, usado somente na criacao da regra.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Enabled,

        [string]$Direction = 'Inbound',
        [string]$Protocol,
        [string]$LocalPort,
        [string[]]$Profile,
        [string]$DisplayName
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Configurar regra de firewall')) {
        return
    }

    $rule = Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue

    if (-not $Enabled) {
        if ($rule) {
            Disable-NetFirewallRule -Name $Name
        }
        return
    }

    $profileValue = if ($Profile -and $Profile.Count -gt 0) { $Profile } else { @('Domain', 'Private') }

    if (-not $rule) {
        $params = @{
            Name        = $Name
            DisplayName = $(if ($DisplayName) { $DisplayName } else { $Name })
            Direction   = $Direction
            Action      = 'Allow'
            Enabled     = 'True'
            Profile     = $profileValue
        }
        if ($Protocol) { $params['Protocol'] = $Protocol }
        if ($LocalPort) { $params['LocalPort'] = $LocalPort }
        New-NetFirewallRule @params | Out-Null
        return
    }

    Enable-NetFirewallRule -Name $Name
    Set-NetFirewallRule -Name $Name -Profile $profileValue
    if ($Protocol -or $LocalPort) {
        $filterParams = @{}
        if ($Protocol) { $filterParams['Protocol'] = $Protocol }
        if ($LocalPort) { $filterParams['LocalPort'] = $LocalPort }
        if ($filterParams.Count -gt 0) {
            Set-NetFirewallRule -Name $Name @filterParams
        }
    }
}
