function Disable-SshServer {
    <#
    .SYNOPSIS
        Para e desabilita o servico sshd.

    .DESCRIPTION
        Para o servico sshd e configura para manual (nao inicia automaticamente).
        Opcionalmente remove a regra de firewall.

    .PARAMETER RemoveFirewallRule
        Remove a regra de firewall 'OpenSSH Server (sshd)'.

    .OUTPUTS
        PSCustomObject com: Success, Message.

    .EXAMPLE
        Disable-SshServer

    .EXAMPLE
        Disable-SshServer -RemoveFirewallRule
    #>
    [CmdletBinding()]
    param(
        [switch]$RemoveFirewallRule
    )

    if (-not (Test-IsAdministrator)) {
        [pscustomobject]@{
            Success = $false
            Message = 'A desabilitacao exige privilegios administrativos.'
        }
        return
    }

    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType Manual -ErrorAction Stop
        Write-Verbose 'Servico sshd parado e configurado para manual.'
    }
    catch { $errors.Add("Service: $($_.Exception.Message)") }

    if ($RemoveFirewallRule) {
        try {
            Remove-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' -ErrorAction SilentlyContinue
            Write-Verbose 'Regra de firewall removida.'
        }
        catch { $errors.Add("Firewall: $($_.Exception.Message)") }
    }

    if ($errors.Count -gt 0) {
        [pscustomobject]@{
            Success = $false
            Message = "Erros: $($errors -join '; ')"
        }
    }
    else {
        [pscustomobject]@{
            Success = $true
            Message = 'SSH Server desabilitado.'
        }
    }
}
