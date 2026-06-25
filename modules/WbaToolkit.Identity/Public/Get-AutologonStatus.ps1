function Get-AutologonStatus {
    <#
    .SYNOPSIS
        Le o estado atual do logon automatico (autologon) do Windows.

    .DESCRIPTION
        Consulta a chave Winlogon e reporta se o autologon esta habilitado, qual a conta
        e dominio configurados, o AutoLogonCount, o ForceAutoLogon, se a senha esta
        armazenada como segredo LSA e se existe (indevidamente) uma senha em texto claro
        no registro. Operacao estritamente de leitura: nao altera o sistema.

        A senha em si NUNCA e lida nem exibida.

    .EXAMPLE
        Get-AutologonStatus

        Retorna o objeto de estado do autologon.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Enabled, UserName, Domain, AutoLogonCount, ForceAutoLogon,
        PasswordInLsa, PlaintextPasswordInRegistry.
    #>
    [CmdletBinding()]
    param()

    $winlogon = Get-WinlogonRegPath
    $props    = Get-ItemProperty -LiteralPath $winlogon -ErrorAction SilentlyContinue

    $autoAdmin = if ($props -and $props.PSObject.Properties['AutoAdminLogon']) { [string]$props.AutoAdminLogon } else { '0' }
    $userName  = if ($props -and $props.PSObject.Properties['DefaultUserName']) { [string]$props.DefaultUserName } else { '' }
    $domain    = if ($props -and $props.PSObject.Properties['DefaultDomainName']) { [string]$props.DefaultDomainName } else { '' }
    $count     = if ($props -and $props.PSObject.Properties['AutoLogonCount']) { $props.AutoLogonCount } else { $null }
    $force     = if ($props -and $props.PSObject.Properties['ForceAutoLogon']) { [string]$props.ForceAutoLogon } else { '0' }
    $plaintext = [bool]($props -and $props.PSObject.Properties['DefaultPassword'] -and -not [string]::IsNullOrEmpty([string]$props.DefaultPassword))

    return [pscustomobject]@{
        Enabled                     = ($autoAdmin -eq '1')
        UserName                    = $userName
        Domain                      = $domain
        AutoLogonCount              = $count
        ForceAutoLogon              = ($force -eq '1')
        PasswordInLsa               = (Test-LsaSecret -Name 'DefaultPassword')
        PlaintextPasswordInRegistry = $plaintext
    }
}
