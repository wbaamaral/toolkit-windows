function Invoke-AutologonManager {
    <#
    .SYNOPSIS
        Gerenciador interativo do logon automatico (autologon) do Windows.

    .DESCRIPTION
        Apresenta o estado atual do autologon e um menu para habilitar, desabilitar ou
        editar. Senhas sao sempre lidas como SecureString (nunca exibidas) e armazenadas
        como segredo LSA. Retorna um array com o registro das operacoes da sessao,
        permitindo que o chamador integre o historico ao seu rastreamento.

    .PARAMETER DryRun
        Simula todas as operacoes sem efetuar alteracoes no sistema.

    .EXAMPLE
        Invoke-AutologonManager

        Inicia o gerenciador interativo em modo real.

    .EXAMPLE
        Invoke-AutologonManager -DryRun

        Inicia o gerenciador em modo de simulacao.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array de objetos com as propriedades: Name, Action, Success, Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $sessionLog = [System.Collections.ArrayList]::new()

    while ($true) {
        $status = Get-AutologonStatus

        Write-Host ''
        Write-Host 'Estado atual do autologon' -ForegroundColor Cyan
        Write-Host ('  Habilitado          : {0}' -f $(if ($status.Enabled) { 'Sim' } else { 'Nao' }))
        Write-Host ('  Usuario             : {0}' -f $status.UserName)
        Write-Host ('  Dominio             : {0}' -f $status.Domain)
        Write-Host ('  AutoLogonCount      : {0}' -f $status.AutoLogonCount)
        Write-Host ('  Senha na LSA        : {0}' -f $(if ($status.PasswordInLsa) { 'Sim' } else { 'Nao' }))
        if ($status.PlaintextPasswordInRegistry) {
            Write-Warn '  ATENCAO: existe senha em TEXTO CLARO no registro (DefaultPassword).'
        }

        Write-Host ''
        Write-Host '[H] Habilitar autologon'
        Write-Host '[D] Desabilitar autologon'
        Write-Host '[E] Editar (usuario/dominio/senha/contagem)'
        Write-Host '[V] Voltar/Sair'
        $action = ([string](Read-Host 'Acao')).Trim().ToUpperInvariant()

        if ($action -in @('', 'V', '0', 'Q', 'SAIR')) {
            break
        }

        $result = $null
        switch ($action) {
            'H' {
                $user = Read-UserInput -Question 'Usuario'
                $dom  = Read-UserInput -Question 'Dominio' -DefaultValue $env:COMPUTERNAME
                $pwd  = Read-Host 'Senha' -AsSecureString
                $params = @{ UserName = $user; Domain = $dom; Password = $pwd; DryRun = $DryRun }
                if (Read-YesNo -Question 'Limitar numero de logons automaticos?' -DefaultYes $false) {
                    $cntText = Read-UserInput -Question 'AutoLogonCount'
                    $cnt = 0
                    if ([int]::TryParse($cntText, [ref]$cnt)) { $params['AutoLogonCount'] = $cnt }
                }
                $result = Enable-Autologon @params
            }
            'D' {
                $clear = Read-YesNo -Question 'Limpar tambem usuario/dominio padrao?' -DefaultYes $false
                $result = Disable-Autologon -ClearUser:$clear -DryRun:$DryRun
            }
            'E' {
                $params = @{ DryRun = $DryRun }
                if (Read-YesNo -Question 'Alterar usuario?' -DefaultYes $false) {
                    $params['UserName'] = Read-UserInput -Question 'Novo usuario'
                }
                if (Read-YesNo -Question 'Alterar dominio?' -DefaultYes $false) {
                    $params['Domain'] = Read-UserInput -Question 'Novo dominio' -DefaultValue $env:COMPUTERNAME
                }
                if (Read-YesNo -Question 'Alterar senha?' -DefaultYes $false) {
                    $params['Password'] = Read-Host 'Nova senha' -AsSecureString
                }
                if (Read-YesNo -Question 'Alterar AutoLogonCount?' -DefaultYes $false) {
                    $cntText = Read-UserInput -Question 'Novo AutoLogonCount'
                    $cnt = 0
                    if ([int]::TryParse($cntText, [ref]$cnt)) { $params['AutoLogonCount'] = $cnt }
                }
                $result = Set-Autologon @params
            }
            default {
                Write-Warn 'Opcao invalida.'
            }
        }

        foreach ($r in @($result)) {
            if ($null -ne $r) { $null = $sessionLog.Add($r) }
        }
    }

    return @($sessionLog)
}
