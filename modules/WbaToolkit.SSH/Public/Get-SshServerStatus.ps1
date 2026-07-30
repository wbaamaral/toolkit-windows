function Get-SshServerStatus {
    <#
    .SYNOPSIS
        Verifica o estado completo do OpenSSH Server no Windows.

    .DESCRIPTION
        Coleta informacoes sobre: feature OpenSSH instalada, servico sshd,
        porta configurada, regra de firewall, chaves de host existentes,
        administrators_authorized_keys e sshd_config.

    .OUTPUTS
        PSCustomObject com: FeatureInstalled, ServiceStatus, ServiceStartType,
        Port, FirewallRule, HostKeys[], AdminKeysCount, ConfigPath, ConfigExists.

    .EXAMPLE
        $status = Get-SshServerStatus
        $status.FeatureInstalled
    #>
    [CmdletBinding()]
    param()

    $paths = Get-SshConfigPath

    $feature = Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OpenSSH.Server*' } |
        Select-Object -First 1

    $featureInstalled = $feature.State -eq 'Installed'

    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue

    $port = 22
    if ($featureInstalled -and (Test-Path -LiteralPath $paths.SshdConfig)) {
        try {
            $configContent = Get-Content -LiteralPath $paths.SshdConfig -ErrorAction SilentlyContinue
            $portLine = $configContent | Where-Object { $_ -match '^\s*Port\s+(\d+)' }
            if ($portLine -match 'Port\s+(\d+)') {
                $port = [int]$Matches[1]
            }
        }
        catch { Write-Verbose "Falha ao ler porta do sshd_config: $($_.Exception.Message)" }
    }

    $fwRule = Get-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $hostKeys = @()
    if ($featureInstalled) {
        $keyPatterns = @('ssh_host_ed25519_key', 'ssh_host_rsa_key', 'ssh_host_ecdsa_key')
        foreach ($pattern in $keyPatterns) {
            $keyPath = Join-Path $paths.HostKeysDir $pattern
            if (Test-Path -LiteralPath $keyPath) {
                $hostKeys += [pscustomobject]@{
                    Type = $pattern -replace 'ssh_host_', '' -replace '_key', ''
                    Path = $keyPath
                }
            }
        }
    }

    $adminKeysCount = 0
    if (Test-Path -LiteralPath $paths.AdminAuthorizedKeys) {
        $adminKeysCount = @(Get-Content -LiteralPath $paths.AdminAuthorizedKeys -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\s*(ssh-rsa|ssh-ed25519|ecdsa-sha2)' }).Count
    }

    [pscustomobject]@{
        FeatureInstalled  = $featureInstalled
        FeatureState      = if ($feature) { $feature.State } else { 'NotFound' }
        ServiceName       = if ($service) { $service.Name } else { 'sshd' }
        ServiceStatus     = if ($service) { $service.Status.ToString() } else { 'NotFound' }
        ServiceStartType  = if ($service) { $service.StartType.ToString() } else { 'Unknown' }
        Port              = $port
        FirewallRuleExists = [bool]$fwRule
        FirewallRuleEnabled = if ($fwRule) { $fwRule.Enabled } else { $null }
        HostKeys          = $hostKeys
        HostKeysCount     = $hostKeys.Count
        AdminKeysCount    = $adminKeysCount
        ConfigPath        = $paths.SshdConfig
        ConfigExists      = (Test-Path -LiteralPath $paths.SshdConfig)
    }
}
