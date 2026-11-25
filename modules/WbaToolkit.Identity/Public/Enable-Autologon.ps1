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

    # Salvaguarda: conta de dominio nao pode ser verificada localmente; exige confirmacao explicita.
    $isLocalAccount = [string]::IsNullOrWhiteSpace($Domain) -or $Domain -ieq $env:COMPUTERNAME -or $Domain -eq '.'
    if (-not $Force -and -not $isLocalAccount) {
        Write-Warn "A conta '$Domain\$UserName' e de dominio; nao e possivel verificar localmente se e privilegiada (ex.: Domain Admin)."
        Write-Warn 'Autologon de conta de dominio potencialmente administrativa e de ALTO RISCO de seguranca fisica.'
        $confirm = Read-UserInput -Question "Digite CONFIRMAR para prosseguir mesmo assim"
        if ($confirm -ne 'CONFIRMAR') {
            Write-Info 'Operacao cancelada (conta de dominio nao confirmada).'
            return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $false; Message = 'Cancelada: conta de dominio nao confirmada.' }
        }
    }
    # Salvaguarda: conta privilegiada exige confirmacao explicita.
    elseif (-not $Force -and (Test-PrivilegedAccount -UserName $UserName -Domain $Domain)) {
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

    $winlogon = $null
    $previousAutoAdminLogon = $null
    $autoAdminLogonWritten = $false
    try {
        Backup-AutologonState | Out-Null

        $winlogon = Get-WinlogonRegPath
        $previousAutoAdminLogon = (Get-ItemProperty -LiteralPath $winlogon -ErrorAction Stop).PSObject.Properties['AutoAdminLogon']

        # Ordem segura: senha (segredo LSA) primeiro e AutoAdminLogon=1 por ultimo.
        # Se qualquer etapa falhar, o autologon nunca fica ligado sem senha.
        # A confirmacao ja ocorreu no ShouldProcess acima; -Confirm:$false evita o
        # prompt aninhado de Set-LsaSecret (ConfirmImpact High), cuja recusa deixava
        # o autologon habilitado sem senha e reportado como sucesso.
        $plain = $null
        $stored = $false
        try {
            $plain = ConvertFrom-SecureStringPlain -Secure $Password
            $stored = Set-LsaSecret -Name 'DefaultPassword' -Value $plain -Confirm:$false
        }
        finally {
            if ($null -ne $plain) { $plain = $null }
        }
        if ($stored -ne $true) {
            throw 'O segredo LSA da senha nao foi gravado.'
        }
        # Texto claro removido do registro se existir.
        Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -ErrorAction SilentlyContinue

        Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName'   -Value $UserName -ErrorAction Stop
        Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Value $Domain   -ErrorAction Stop
        if ($PSBoundParameters.ContainsKey('AutoLogonCount')) {
            Set-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -Value $AutoLogonCount -Type DWord -ErrorAction Stop
        }

        $autoAdminLogonWritten = $true
        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value '1' -ErrorAction Stop

        Write-Ok "Autologon habilitado para '$Domain\$UserName'."
        return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $true; Message = 'OK.' }
    }
    catch {
        $failure = $_.Exception.Message
        # Rollback: se a escrita final de AutoAdminLogon foi tentada e falhou,
        # devolve o valor anterior; as etapas anteriores nao ligam o autologon.
        if ($autoAdminLogonWritten -and $winlogon) {
            try {
                $restoreValue = if ($previousAutoAdminLogon) { [string]$previousAutoAdminLogon.Value } else { '0' }
                Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value $restoreValue -ErrorAction Stop
            }
            catch {
                Write-Warn "Nao foi possivel restaurar AutoAdminLogon: $($_.Exception.Message)"
            }
        }
        Write-Fail "Falha ao habilitar autologon: $failure"
        return [pscustomobject]@{ Name = $UserName; Action = 'Enable'; Success = $false; Message = $failure }
    }
}
