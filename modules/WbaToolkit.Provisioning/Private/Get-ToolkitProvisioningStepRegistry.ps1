function Get-ToolkitProvisioningStepRegistry {
    <#
    .SYNOPSIS
        Devolve o manifesto das etapas instaladas nesta versao do modulo.

    .DESCRIPTION
        Fase 1 (nucleo seguro): preflight.system, identity.hostname, computer.locale,
        validation.final, cleanup.finalize. Fase 2 (rede e acesso remoto): network.configure,
        certificates.install, remoteaccess.winrm, remoteaccess.rdp, firewall.rules —
        inseridas entre computer.locale e validation.final. Conforme SPEC-PROVISIONING-TESTS.
        O JSON de configuracao nunca indica caminho de script ou nome de funcao — apenas
        este registro interno decide o que executa.

    .OUTPUTS
        System.Collections.Hashtable[] — um manifesto por etapa.
    #>
    [CmdletBinding()]
    param()

    @(
        @{
            Id               = 'preflight.system'
            Version          = '1.0.0'
            Phase            = 'Finalization'
            DependsOn        = @()
            ConfigSection    = $null
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitPreflightDesiredState'
            SetFunction      = 'Set-ToolkitPreflightDesiredState'
            VerifyFunction   = 'Test-ToolkitPreflightDesiredState'
        },
        @{
            Id               = 'identity.hostname'
            Version          = '1.0.0'
            Phase            = 'Identity'
            DependsOn        = @('preflight.system')
            ConfigSection    = 'computer'
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $true
            TestFunction     = 'Test-ToolkitHostnameDesiredState'
            SetFunction      = 'Set-ToolkitHostnameDesiredState'
            VerifyFunction   = 'Test-ToolkitHostnameDesiredState'
        },
        @{
            Id               = 'computer.locale'
            Version          = '1.0.0'
            Phase            = 'Identity'
            DependsOn        = @('identity.hostname')
            ConfigSection    = 'computer'
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $true
            TestFunction     = 'Test-ToolkitLocaleDesiredState'
            SetFunction      = 'Set-ToolkitLocaleDesiredState'
            VerifyFunction   = 'Test-ToolkitLocaleDesiredState'
        },
        @{
            Id               = 'network.configure'
            Version          = '1.0.0'
            Phase            = 'Networking'
            DependsOn        = @('computer.locale')
            ConfigSection    = 'network'
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitNetworkDesiredState'
            SetFunction      = 'Set-ToolkitNetworkDesiredState'
            VerifyFunction   = 'Test-ToolkitNetworkDesiredState'
        },
        @{
            Id               = 'certificates.install'
            Version          = '1.0.0'
            Phase            = 'Security'
            DependsOn        = @('network.configure')
            ConfigSection    = 'certificates'
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitCertificateDesiredState'
            SetFunction      = 'Set-ToolkitCertificateDesiredState'
            VerifyFunction   = 'Test-ToolkitCertificateDesiredState'
        },
        @{
            Id               = 'remoteaccess.winrm'
            Version          = '1.0.0'
            Phase            = 'Security'
            DependsOn        = @('certificates.install')
            ConfigSection    = 'remoteAccess.winrm'
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitWinRmDesiredState'
            SetFunction      = 'Set-ToolkitWinRmDesiredState'
            VerifyFunction   = 'Test-ToolkitWinRmDesiredState'
        },
        @{
            Id               = 'remoteaccess.rdp'
            Version          = '1.0.0'
            Phase            = 'Security'
            DependsOn        = @('remoteaccess.winrm')
            ConfigSection    = 'remoteAccess.rdp'
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitRdpDesiredState'
            SetFunction      = 'Set-ToolkitRdpDesiredState'
            VerifyFunction   = 'Test-ToolkitRdpDesiredState'
        },
        @{
            Id               = 'firewall.rules'
            Version          = '1.0.0'
            Phase            = 'Security'
            DependsOn        = @('remoteaccess.rdp')
            ConfigSection    = 'firewall'
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitFirewallRulesDesiredState'
            SetFunction      = 'Set-ToolkitFirewallRulesDesiredState'
            VerifyFunction   = 'Test-ToolkitFirewallRulesDesiredState'
        },
        @{
            Id               = 'validation.final'
            Version          = '1.0.0'
            Phase            = 'Finalization'
            DependsOn        = @('firewall.rules')
            ConfigSection    = $null
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitFinalValidationDesiredState'
            SetFunction      = 'Set-ToolkitFinalValidationDesiredState'
            VerifyFunction   = 'Test-ToolkitFinalValidationDesiredState'
        },
        @{
            Id               = 'cleanup.finalize'
            Version          = '1.0.0'
            Phase            = 'Finalization'
            DependsOn        = @('validation.final')
            ConfigSection    = $null
            RequiresAdmin    = $true
            SupportsWhatIf   = $true
            MayRequestReboot = $false
            TestFunction     = 'Test-ToolkitCleanupFinalizeDesiredState'
            SetFunction      = 'Set-ToolkitCleanupFinalizeDesiredState'
            VerifyFunction   = 'Test-ToolkitCleanupFinalizeDesiredState'
        }
    )
}
