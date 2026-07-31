function Enable-SshServer {
    <#
    .SYNOPSIS
        Habilita e inicia o servico sshd com regra de firewall.

    .DESCRIPTION
        Configura o servico sshd para iniciar automaticamente, inicia o servico
        e cria a regra de firewall para permitir conexao na porta TCP configurada.

    .PARAMETER Port
        Porta TCP para a regra de firewall. Padrao: 22.

    .OUTPUTS
        PSCustomObject com: Success, Message, Port.

    .EXAMPLE
        Enable-SshServer

    .EXAMPLE
        Enable-SshServer -Port 2222
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 65535)]
        [int]$Port = 22
    )

    if (-not (Test-IsAdministrator)) {
        [pscustomobject]@{
            Success = $false
            Message = 'A habilitacao exige privilegios administrativos.'
            Port    = $Port
        }
        return
    }

    $current = Get-SshServerStatus
    if (-not $current.FeatureInstalled) {
        [pscustomobject]@{
            Success = $false
            Message = 'OpenSSH Server nao esta instalado. Execute Install-SshServer primeiro.'
            Port    = $Port
        }
        return
    }

    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
        Write-Verbose 'Servico sshd configurado para iniciar automaticamente.'
    }
    catch { $errors.Add("StartupType: $($_.Exception.Message)") }

    try {
        Start-Service -Name sshd -ErrorAction Stop
        Write-Verbose 'Servico sshd iniciado.'
    }
    catch { $errors.Add("Start: $($_.Exception.Message)") }

    $fwRule = Get-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $fwRule) {
        try {
            New-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' `
                -Direction Inbound -Protocol TCP -LocalPort $Port `
                -Action Allow -ErrorAction Stop | Out-Null
            Write-Verbose "Regra de firewall criada na porta $Port."
        }
        catch { $errors.Add("Firewall: $($_.Exception.Message)") }
    }
    else {
        $currentPort = ($fwRule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue).LocalPort
        if ($currentPort -ne $Port) {
            try {
                $fwRule | Set-NetFirewallRule -ErrorAction Stop
                $fwRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port -ErrorAction Stop
                Write-Verbose "Porta da regra de firewall atualizada para $Port."
            }
            catch { $errors.Add("Firewall update: $($_.Exception.Message)") }
        }
    }

    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $statusNow = if ($service) { $service.Status.ToString() } else { 'Unknown' }

    if ($errors.Count -gt 0) {
        [pscustomobject]@{
            Success = $false
            Message = "Erros: $($errors -join '; ')"
            Port    = $Port
        }
    }
    else {
        [pscustomobject]@{
            Success = $true
            Message = "SSH Server habilitado. Servico: $statusNow | Porta: $Port"
            Port    = $Port
        }
    }
}
