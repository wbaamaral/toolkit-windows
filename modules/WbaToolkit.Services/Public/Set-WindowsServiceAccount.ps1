function Set-WindowsServiceAccount {
    <#
    .SYNOPSIS
        Configura a conta de logon de um servico Windows.

    .DESCRIPTION
        Altera a conta utilizada para executar o servico. Suporta LocalSystem,
        LocalService, NetworkService ou conta de dominio com senha.

    .PARAMETER Name
        Nome do servico.

    .PARAMETER Account
        Conta de logon: 'LocalSystem', 'LocalService', 'NetworkService' ou 'DOMINIO\usuario'.

    .PARAMETER Credential
        Credencial segura da conta. Obrigatoria para contas que nao sejam Built-in.

    .OUTPUTS
        PSCustomObject com: Success, Message, ServiceName, Changes.

    .EXAMPLE
        Set-WindowsServiceAccount -Name 'MeuServico' -Account 'NETWORK SERVICE'

    .EXAMPLE
        $credential = Get-Credential -UserName 'DOMINIO\svc_meu'
        Set-WindowsServiceAccount -Name 'MeuServico' -Account 'DOMINIO\svc_meu' -Credential $credential
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Account,

        [pscredential]$Credential
    )

    if (-not (Test-IsAdministrator)) {
        return Format-ServiceResult -Success $false -Message 'A operacao exige privilegios administrativos.'
    }

    $resolved = Resolve-WindowsService -Name $Name
    if (-not $resolved.Exists) {
        return Format-ServiceResult -Success $false -Message $resolved.Message -ServiceName $Name
    }

    $wmi = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    $currentAccount = if ($wmi) { $wmi.StartName } else { 'Unknown' }

    $builtIn = @('LocalSystem', 'NT AUTHORITY\LocalService', 'NT AUTHORITY\NetworkService',
                  '.\LocalService', '.\NetworkService', 'LocalService', 'NetworkService',
                  'NT AUTHORITY\\LocalService', 'NT AUTHORITY\\NetworkService')

    $needsPassword = ($Account -notin $builtIn) -and ($Account -ne 'LocalSystem')

    if ($needsPassword -and $null -eq $Credential) {
        return Format-ServiceResult -Success $false -Message "Conta '$Account' requer -Credential." -ServiceName $Name
    }

    if ($needsPassword -and $Credential.UserName -ne $Account) {
        return Format-ServiceResult -Success $false -Message 'O usuário de -Credential deve corresponder a -Account.' -ServiceName $Name
    }

    try {
        if (-not $PSCmdlet.ShouldProcess($Name, "Alterar conta de logon para $Account")) {
            return Format-ServiceResult -Success $true -Message 'WhatIf: nenhuma alteração aplicada.' -ServiceName $Name
        }

        if ($needsPassword) {
            $wmi | Invoke-CimMethod -MethodName Change -Arguments @{
                StartName = $Account
                StartPassword = $Credential.GetNetworkCredential().Password
            } | Out-Null
        }
        else {
            $wmi | Invoke-CimMethod -MethodName Change -Arguments @{
                StartName = $Account
            } | Out-Null
        }

        Format-ServiceResult -Success $true -Message "Servico '$Name' alterado de $currentAccount para $Account." -ServiceName $Name -Changes @("Account: $currentAccount -> $Account")
    }
    catch {
        Format-ServiceResult -Success $false -Message "Erro ao alterar conta de '$Name': $($_.Exception.Message)" -ServiceName $Name
    }
}
