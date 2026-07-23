function Disable-Autologon {
    <#
    .SYNOPSIS
        Desabilita o logon automatico do Windows.

    .DESCRIPTION
        Grava AutoAdminLogon=0, limpa a senha armazenada como segredo LSA
        ('DefaultPassword') e remove DefaultPassword (texto claro, se existir) e
        AutoLogonCount do registro. Faz backup dos valores atuais antes de alterar.
        Idempotente: avisa se o autologon ja estava desabilitado.

    .PARAMETER KeepUserName
        Mantem DefaultUserName/DefaultDomainName no registro (apenas desliga o autologon).
        Por padrao, esses valores sao preservados; use -ClearUser para limpa-los.

    .PARAMETER ClearUser
        Tambem limpa DefaultUserName e DefaultDomainName.

    .PARAMETER DryRun
        Simula a operacao sem alterar o sistema.

    .EXAMPLE
        Disable-Autologon

        Desabilita o autologon, preservando o nome de usuario configurado.

    .EXAMPLE
        Disable-Autologon -ClearUser -DryRun

        Simula a desativacao limpando tambem o usuario padrao.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Name, Action, Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)][switch]$ClearUser,
        [Parameter(Mandatory = $false)][switch]$DryRun
    )

    $status = Get-AutologonStatus
    if (-not $status.Enabled -and -not $status.PasswordInLsa -and -not $status.PlaintextPasswordInRegistry) {
        Write-Warn 'Autologon ja esta desabilitado.'
        return [pscustomobject]@{ Name = $status.UserName; Action = 'Disable'; Success = $false; Message = 'Ja desabilitado.' }
    }

    if ($DryRun) {
        Write-Verbose 'DRY-RUN: desabilitaria o autologon.'
        return [pscustomobject]@{ Name = $status.UserName; Action = 'Disable'; Success = $true; Message = 'DryRun.' }
    }

    if (-not $PSCmdlet.ShouldProcess('Autologon', 'Desabilitar autologon')) {
        return [pscustomobject]@{ Name = $status.UserName; Action = 'Disable'; Success = $true; Message = 'WhatIf.' }
    }

    try {
        Backup-AutologonState | Out-Null

        $winlogon = Get-WinlogonRegPath
        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value '0' -ErrorAction Stop
        Clear-LsaSecret -Name 'DefaultPassword'
        Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount'  -ErrorAction SilentlyContinue

        if ($ClearUser) {
            Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName'   -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -ErrorAction SilentlyContinue
        }

        Write-Ok 'Autologon desabilitado.'
        return [pscustomobject]@{ Name = $status.UserName; Action = 'Disable'; Success = $true; Message = 'OK.' }
    }
    catch {
        Write-Fail "Falha ao desabilitar autologon: $($_.Exception.Message)"
        return [pscustomobject]@{ Name = $status.UserName; Action = 'Disable'; Success = $false; Message = $_.Exception.Message }
    }
}
