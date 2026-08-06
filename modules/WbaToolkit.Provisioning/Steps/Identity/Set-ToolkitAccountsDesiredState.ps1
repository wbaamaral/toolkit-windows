function Set-ToolkitAccountsDesiredState {
    <#
    .SYNOPSIS
        Etapa accounts.local — cria/remove contas locais e ajusta pertencimento a grupos.

    .DESCRIPTION
        Senha somente via secretRef; senha vazia e recusada. Conta ja existente nunca tem
        a senha redefinida (idempotencia sem re-leitura de segredo em execucoes
        subsequentes). Grupos ausentes sao adicionados; grupos nao declarados nunca sao
        removidos. Contas built-in (RID 500/501/503/504 — Administrator, Guest,
        DefaultAccount, WDAGUtilityAccount) nunca sao removidas, mesmo se declaradas
        'Absent' por engano (defesa em profundidade).

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $builtInRidPattern = '-(500|501|503|504)$'
    $applied = @()

    foreach ($entry in @($Context.Config.accounts)) {
        $ensure = if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'ensure') { [string]$entry.ensure } else { 'Present' }
        $user = Get-LocalUser -Name $entry.name -ErrorAction SilentlyContinue

        if ($ensure -eq 'Absent') {
            if (-not $user) {
                continue
            }
            if ($user.SID.Value -match $builtInRidPattern) {
                throw "Conta '$($entry.name)' e uma conta built-in (SID $($user.SID.Value)); remocao recusada."
            }
            if ($PSCmdlet.ShouldProcess($entry.name, 'Remover conta local')) {
                Remove-LocalUser -Name $entry.name
                $applied += $entry.name
            }
            continue
        }

        if (-not $user) {
            if (-not (Test-ToolkitPropertyPresent -InputObject $entry -Name 'password') -or
                -not (Test-ToolkitPropertyPresent -InputObject $entry.password -Name 'secretRef') -or
                [string]::IsNullOrWhiteSpace([string]$entry.password.secretRef)) {
                throw "Conta '$($entry.name)': senha ausente ou nao referenciada por secretRef; criacao recusada."
            }

            if (-not $PSCmdlet.ShouldProcess($entry.name, 'Criar conta local')) {
                continue
            }

            $securePassword = Resolve-ToolkitProvisioningSecret -SecretRef ([string]$entry.password.secretRef) -Paths $Context.Paths
            try {
                if (-not $securePassword -or $securePassword.Length -eq 0) {
                    throw "Conta '$($entry.name)': secretRef '$($entry.password.secretRef)' resolveu para senha vazia; criacao recusada."
                }
                New-LocalUser -Name $entry.name -Password $securePassword -PasswordNeverExpires:$false -AccountNeverExpires | Out-Null
            }
            finally {
                $securePassword = $null
            }
            $user = Get-LocalUser -Name $entry.name
            $applied += $entry.name
        }

        $declaredGroups = if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'groups') { @($entry.groups) } else { @() }
        foreach ($groupName in $declaredGroups) {
            $group = Resolve-ToolkitLocalGroup -Name $groupName
            if (-not $group) {
                throw "Grupo '$groupName' declarado para a conta '$($entry.name)' nao existe nesta maquina."
            }
            # -Name (string) em vez de -Group/-Member (LocalGroup/LocalPrincipal): parametro
            # primitivo, mockavel sem exigir instancia real do tipo forte (padrao-powershell-
            # practice-and-style.md #6.7).
            $isMember = [bool](Get-LocalGroupMember -Name $group.Name -ErrorAction SilentlyContinue | Where-Object { $_.SID -eq $user.SID })
            if (-not $isMember -and $PSCmdlet.ShouldProcess("$($entry.name) -> $groupName", 'Adicionar a grupo local')) {
                Add-LocalGroupMember -Name $group.Name -Member $user.Name
                if ($applied -notcontains $entry.name) { $applied += $entry.name }
            }
        }
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Contas ajustadas: $($applied -join ', ')."
        Evidence       = [pscustomobject]@{ AppliedAccounts = $applied }
    }
}
