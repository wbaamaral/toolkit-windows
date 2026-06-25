function Set-Autologon {
    <#
    .SYNOPSIS
        Edita parametros do autologon sem alternar seu estado habilitado/desabilitado.

    .DESCRIPTION
        Altera DefaultUserName, DefaultDomainName e/ou AutoLogonCount, e opcionalmente
        re-grava a senha (como segredo LSA), preservando o valor atual de AutoAdminLogon.
        Faz backup antes de alterar. Util para corrigir a conta ou ajustar o contador
        sem precisar reabilitar todo o autologon.

        Se a conta passar a ser privilegiada, aplica a mesma confirmacao de Enable-Autologon.

    .PARAMETER UserName
        Novo nome de usuario. Quando omitido, mantem o atual.

    .PARAMETER Domain
        Novo dominio. Quando omitido, mantem o atual.

    .PARAMETER Password
        Nova senha (SecureString) a re-gravar como segredo LSA. Quando omitida, mantem a atual.

    .PARAMETER AutoLogonCount
        Novo AutoLogonCount. Quando omitido, mantem o atual.

    .PARAMETER Force
        Pula a confirmacao de conta privilegiada.

    .PARAMETER DryRun
        Simula a operacao sem alterar o sistema.

    .EXAMPLE
        Set-Autologon -AutoLogonCount 3

        Ajusta apenas o numero de logons automaticos restantes.

    .EXAMPLE
        Set-Autologon -UserName 'recepcao' -Password (Read-Host -AsSecureString)

        Troca a conta e a senha do autologon, mantendo o estado atual.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Name, Action, Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)][string]$UserName,
        [Parameter(Mandatory = $false)][string]$Domain,
        [Parameter(Mandatory = $false)][System.Security.SecureString]$Password,
        [Parameter(Mandatory = $false)][int]$AutoLogonCount,
        [Parameter(Mandatory = $false)][switch]$Force,
        [Parameter(Mandatory = $false)][switch]$DryRun
    )

    if (-not ($PSBoundParameters.ContainsKey('UserName') -or $PSBoundParameters.ContainsKey('Domain') -or
              $PSBoundParameters.ContainsKey('Password') -or $PSBoundParameters.ContainsKey('AutoLogonCount'))) {
        Write-Warn 'Nada a editar: informe ao menos um de -UserName, -Domain, -Password ou -AutoLogonCount.'
        return [pscustomobject]@{ Name = ''; Action = 'Set'; Success = $false; Message = 'Nenhum campo informado.' }
    }

    $status         = Get-AutologonStatus
    $effectiveUser  = if ($PSBoundParameters.ContainsKey('UserName')) { $UserName } else { $status.UserName }
    $effectiveDomain = if ($PSBoundParameters.ContainsKey('Domain')) { $Domain } else { $status.Domain }
    if ([string]::IsNullOrWhiteSpace($effectiveDomain)) { $effectiveDomain = $env:COMPUTERNAME }

    if (-not $Force -and $PSBoundParameters.ContainsKey('UserName') -and
        (Test-PrivilegedAccount -UserName $effectiveUser -Domain $effectiveDomain)) {
        Write-Warn "A conta '$effectiveDomain\$effectiveUser' e privilegiada (Administradores)."
        $confirm = Read-UserInput -Question "Digite CONFIRMAR para prosseguir mesmo assim"
        if ($confirm -ne 'CONFIRMAR') {
            Write-Info 'Operacao cancelada (conta privilegiada nao confirmada).'
            return [pscustomobject]@{ Name = $effectiveUser; Action = 'Set'; Success = $false; Message = 'Cancelada: conta privilegiada.' }
        }
    }

    if ($DryRun) {
        Write-Verbose 'DRY-RUN: editaria parametros do autologon.'
        return [pscustomobject]@{ Name = $effectiveUser; Action = 'Set'; Success = $true; Message = 'DryRun.' }
    }

    if (-not $PSCmdlet.ShouldProcess('Autologon', 'Editar parametros do autologon')) {
        return [pscustomobject]@{ Name = $effectiveUser; Action = 'Set'; Success = $true; Message = 'WhatIf.' }
    }

    try {
        Backup-AutologonState | Out-Null
        $winlogon = Get-WinlogonRegPath

        if ($PSBoundParameters.ContainsKey('UserName')) {
            Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName' -Value $UserName -ErrorAction Stop
        }
        if ($PSBoundParameters.ContainsKey('Domain')) {
            Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Value $Domain -ErrorAction Stop
        }
        if ($PSBoundParameters.ContainsKey('AutoLogonCount')) {
            Set-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -Value $AutoLogonCount -Type DWord -ErrorAction Stop
        }
        if ($PSBoundParameters.ContainsKey('Password')) {
            $plain = $null
            try {
                $plain = ConvertFrom-SecureStringPlain -Secure $Password
                Set-LsaSecret -Name 'DefaultPassword' -Value $plain
            }
            finally {
                if ($null -ne $plain) { $plain = $null }
            }
            Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -ErrorAction SilentlyContinue
        }

        Write-Ok 'Parametros do autologon atualizados.'
        return [pscustomobject]@{ Name = $effectiveUser; Action = 'Set'; Success = $true; Message = 'OK.' }
    }
    catch {
        Write-Fail "Falha ao editar autologon: $($_.Exception.Message)"
        return [pscustomobject]@{ Name = $effectiveUser; Action = 'Set'; Success = $false; Message = $_.Exception.Message }
    }
}
