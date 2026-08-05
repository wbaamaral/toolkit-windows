function Get-ToolkitProvisioningStepRegistry {
    <#
    .SYNOPSIS
        Devolve o manifesto das etapas instaladas nesta versao do modulo.

    .DESCRIPTION
        Fase 1 (nucleo seguro) registra somente preflight.system, identity.hostname,
        computer.locale, validation.final e cleanup.finalize, conforme
        SPEC-PROVISIONING-TESTS. O JSON de configuracao nunca indica caminho de script
        ou nome de funcao — apenas este registro interno decide o que executa.

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
            Id               = 'validation.final'
            Version          = '1.0.0'
            Phase            = 'Finalization'
            DependsOn        = @('computer.locale')
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
