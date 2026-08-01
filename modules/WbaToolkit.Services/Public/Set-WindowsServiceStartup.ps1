function Set-WindowsServiceStartup {
    <#
    .SYNOPSIS
        Configura o tipo de inicializacao de um servico Windows.

    .DESCRIPTION
        Altera o StartType do servico (Automatic, Manual, Disabled).

    .PARAMETER Name
        Nome do servico.

    .PARAMETER StartupType
        Novo tipo de inicializacao: Automatic, Manual, Disabled.

    .OUTPUTS
        PSCustomObject com: Success, Message, ServiceName, Changes.

    .EXAMPLE
        Set-WindowsServiceStartup -Name 'WSearch' -StartupType Disabled

    .EXAMPLE
        Set-WindowsServiceStartup -Name 'Spooler' -StartupType Manual
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartupType
    )

    if (-not (Test-IsAdministrator)) {
        return Format-ServiceResult -Success $false -Message 'A operacao exige privilegios administrativos.'
    }

    $resolved = Resolve-WindowsService -Name $Name
    if (-not $resolved.Exists) {
        return Format-ServiceResult -Success $false -Message $resolved.Message -ServiceName $Name
    }

    $wmi = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    $currentType = if ($wmi) { $wmi.StartMode } else { 'Unknown' }

    if ($currentType -eq $StartupType) {
        return Format-ServiceResult -Success $true -Message "Servico '$Name' ja esta configurado como $StartupType." -ServiceName $Name
    }

    if (-not $PSCmdlet.ShouldProcess($Name, "Alterar tipo de inicializacao para $StartupType")) {
        return Format-ServiceResult -Success $true -Message "Alteracao de inicializacao de '$Name' ignorada por WhatIf." -ServiceName $Name
    }

    try {
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        Format-ServiceResult -Success $true -Message "Servico '$Name' alterado de $currentType para $StartupType." -ServiceName $Name -Changes @("StartupType: $currentType -> $StartupType")
    }
    catch {
        Format-ServiceResult -Success $false -Message "Erro ao alterar inicializacao de '$Name': $($_.Exception.Message)" -ServiceName $Name
    }
}
