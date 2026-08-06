function Test-ToolkitAccountsDesiredState {
    <#
    .SYNOPSIS
        Etapa accounts.local — verifica contas e grupos locais declarados.

    .DESCRIPTION
        Nunca compara senha (nao ha como ler de volta um valor ja hasheado pelo Windows);
        conta existente e considerada conforme quanto a senha — criacao e idempotente, nao
        redefine senha em execucoes subsequentes (SPEC-PROVISIONING-TESTS: 'criacao
        idempotente de conta/grupo'). Verifica apenas existencia e pertencimento aos
        grupos declarados.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status, Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $config = $Context.Config
    if (-not (Test-ToolkitPropertyPresent -InputObject $config -Name 'accounts')) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'accounts' nao declarada."; Evidence = $null }
    }

    $entries = @($config.accounts)
    if ($entries.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "'accounts' esta vazio."; Evidence = $null }
    }

    $evaluations = @()
    foreach ($entry in $entries) {
        $ensure = if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'ensure') { [string]$entry.ensure } else { 'Present' }
        $user = Get-LocalUser -Name $entry.name -ErrorAction SilentlyContinue

        if ($ensure -eq 'Absent') {
            $evaluations += [pscustomobject]@{ Name = $entry.name; IsCompliant = (-not $user); Detail = 'Ausente' }
            continue
        }

        if (-not $user) {
            $evaluations += [pscustomobject]@{ Name = $entry.name; IsCompliant = $false; Detail = 'Conta nao existe' }
            continue
        }

        $missingGroups = @()
        $declaredGroups = if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'groups') { @($entry.groups) } else { @() }
        foreach ($groupName in $declaredGroups) {
            $group = Resolve-ToolkitLocalGroup -Name $groupName
            $isMember = $false
            if ($group) {
                # -Name (string) em vez de -Group (LocalGroup) — ver Set-ToolkitAccountsDesiredState.
                $isMember = [bool](Get-LocalGroupMember -Name $group.Name -ErrorAction SilentlyContinue | Where-Object { $_.SID -eq $user.SID })
            }
            if (-not $isMember) {
                $missingGroups += $groupName
            }
        }

        $evaluations += [pscustomobject]@{
            Name          = $entry.name
            IsCompliant   = ($missingGroups.Count -eq 0)
            Detail        = $(if ($missingGroups.Count -gt 0) { "Grupos pendentes: $($missingGroups -join ', ')" } else { 'Conforme' })
            MissingGroups = $missingGroups
        }
    }

    $nonCompliant = @($evaluations | Where-Object { -not $_.IsCompliant })
    $evidence = [pscustomobject]@{ Accounts = $evaluations }

    if ($nonCompliant.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'Todas as contas declaradas ja atendem a configuracao.'; Evidence = $evidence }
    }

    $names = ($nonCompliant | ForEach-Object { $_.Name }) -join ', '
    return [pscustomobject]@{ Status = 'Changed'; Message = "Contas pendentes: $names."; Evidence = $evidence }
}
