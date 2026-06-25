function Enable-Autologon {
    <#
    .SYNOPSIS
        Habilita o logon automatico do Windows para a conta informada.

    .DESCRIPTION
        Configura o autologon gravando AutoAdminLogon=1, DefaultUserName e
        DefaultDomainName na chave Winlogon e armazenando a senha como segredo LSA
        ('DefaultPassword'), sem nunca gravar a senha em texto claro no registro
        (conformidade ADR 0005). Faz backup dos valores atuais antes de alterar.

        Salvaguardas: confirma explicitamente quando a conta alvo for privilegiada
        (membro de Administradores); suporta AutoLogonCount para limitar o numero de
        logons automaticos; suporta -DryRun e -WhatIf.

    .PARAMETER UserName
        Conta que fara o logon automatico.

    .PARAMETER Domain
        Dominio da conta. Padrao: nome da maquina (conta local).

    .PARAMETER Credential
        Credencial (usuario + senha) da conta. Alternativa a -Password; quando informada,
        UserName/Domain podem ser derivados dela se omitidos.

    .PARAMETER Password
        Senha da conta como SecureString. Alternativa a -Credential.

    .PARAMETER AutoLogonCount
        Numero de logons automaticos antes de o Windows desativar o autologon.
        Quando omitido, o autologon permanece ate ser desabilitado.

    .PARAMETER Force
        Pula a confirmacao interativa de conta privilegiada (use com cautela em automacao).

    .PARAMETER DryRun
        Simula a operacao sem alterar o sistema.

    .EXAMPLE
        Enable-Autologon -UserName 'kiosk' -Password (Read-Host -AsSecureString)

        Habilita autologon para a conta local 'kiosk'.

    .EXAMPLE
        Enable-Autologon -Credential (Get-Credential) -AutoLogonCount 1 -DryRun

        Simula a habilitacao com apenas um logon automatico.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Name, Action, Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)][string]$UserName,
        [Parameter(Mandatory = $false)][string]$Domain = $env:COMPUTERNAME,
        [Parameter(Mandatory = $false)][pscredential]$Credential,
        [Parameter(Mandatory = $false)][System.Security.SecureString]$Password,
        [Parameter(Mandatory = $false)][int]$AutoLogonCount,
        [Parameter(Mandatory = $false)][switch]$Force,
        [Parameter(Mandatory = $false)][switch]$DryRun
    )

    # Resolve usuario/dominio/senha a partir de -Credential quando aplicavel.
    if ($Credential) {
        if ([string]::IsNullOrWhiteSpace($UserName)) {
            $netCred  = $Credential.GetNetworkCredential()
            $UserName = $netCred.UserName
            if (-not [string]::IsNullOrWhiteSpace($netCred.Domain)) { $Domain = $netCred.Domain }
        }
        if (-not $Password) { $Password = $Credential.Password }
    }

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        Write-Fail 'UserName e obrigatorio (informe -UserName ou -Credential).'
        return [pscustomobject]@{ Name = ''; Action = 'Enable'; Success = $false; Message = 'UserName ausente.' }
    }
    if (-not $Password) {
        Write-Fail 'Senha e obrigatoria (informe -Password ou -Credential).'
        return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $false; Message = 'Senha ausente.' }
    }

    # Salvaguarda: conta privilegiada exige confirmacao explicita.
    if (-not $Force -and (Test-PrivilegedAccount -UserName $UserName -Domain $Domain)) {
        Write-Warn "A conta '$Domain\$UserName' e privilegiada (Administradores)."
        Write-Warn 'Autologon de conta administradora e de ALTO RISCO de seguranca fisica.'
        $confirm = Read-UserInput -Question "Digite CONFIRMAR para prosseguir mesmo assim"
        if ($confirm -ne 'CONFIRMAR') {
            Write-Info 'Operacao cancelada (conta privilegiada nao confirmada).'
            return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $false; Message = 'Cancelada: conta privilegiada.' }
        }
    }

    if ($DryRun) {
        Write-Verbose "DRY-RUN: habilitaria autologon de '$Domain\$UserName'."
        $msg = if ($PSBoundParameters.ContainsKey('AutoLogonCount')) { "DryRun (AutoLogonCount=$AutoLogonCount)." } else { 'DryRun.' }
        return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $true; Message = $msg }
    }

    if (-not $PSCmdlet.ShouldProcess("$Domain\$UserName", 'Habilitar autologon')) {
        return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $true; Message = 'WhatIf.' }
    }

    try {
        Backup-AutologonState | Out-Null

        $winlogon = Get-WinlogonRegPath
        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon'    -Value '1'       -ErrorAction Stop
        Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName'   -Value $UserName -ErrorAction Stop
        Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Value $Domain   -ErrorAction Stop

        # Senha via segredo LSA; texto claro removido do registro se existir.
        $plain = $null
        try {
            $plain = ConvertFrom-SecureStringPlain -Secure $Password
            Set-LsaSecret -Name 'DefaultPassword' -Value $plain
        }
        finally {
            if ($null -ne $plain) { $plain = $null }
        }
        Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -ErrorAction SilentlyContinue

        if ($PSBoundParameters.ContainsKey('AutoLogonCount')) {
            Set-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -Value $AutoLogonCount -Type DWord -ErrorAction Stop
        }

        Write-Ok "Autologon habilitado para '$Domain\$UserName'."
        return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $true; Message = 'OK.' }
    }
    catch {
        Write-Fail "Falha ao habilitar autologon: $($_.Exception.Message)"
        return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $false; Message = $_.Exception.Message }
    }
}
