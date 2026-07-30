function Install-SshServer {
    <#
    .SYNOPSIS
        Instala o OpenSSH Server como feature opcional do Windows.

    .DESCRIPTION
        Instala a feature OpenSSH.Server via Add-WindowsCapability.
        A feature ja vem disponivel no Windows 10 (1809+), 11 e Server 2019+.

    .OUTPUTS
        PSCustomObject com: Success, Message.

    .EXAMPLE
        Install-SshServer
    #>
    [CmdletBinding()]
    param()

    $current = Get-SshServerStatus

    if ($current.FeatureInstalled) {
        [pscustomobject]@{
            Success = $true
            Message = 'OpenSSH Server ja esta instalado.'
        }
        return
    }

    if (-not (Test-IsAdministrator)) {
        [pscustomobject]@{
            Success = $false
            Message = 'A instalacao exige privilegios administrativos.'
        }
        return
    }

    try {
        Write-Verbose 'Instalando OpenSSH.Server via Add-WindowsCapability...'
        $result = Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction Stop
        [pscustomobject]@{
            Success = $true
            Message = "OpenSSH.Server instalado com sucesso. Estado: $($result.State)"
        }
    }
    catch {
        [pscustomobject]@{
            Success = $false
            Message = "Falha ao instalar: $($_.Exception.Message)"
        }
    }
}
