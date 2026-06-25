function Test-PrivilegedAccount {
    <#
    .SYNOPSIS
        Indica se a conta local informada pertence ao grupo Administradores.

    .DESCRIPTION
        Consulta a associacao de grupos locais para determinar se a conta alvo do
        autologon e privilegiada. Habilitar autologon de uma conta administradora e
        de alto risco de seguranca fisica; o chamador usa este resultado para exigir
        confirmacao explicita.

        A verificacao e feita apenas para contas locais (Domain vazio ou igual ao
        nome da maquina). Para contas de dominio, retorna $false (indeterminado local)
        e cabe ao chamador alertar separadamente.

    .PARAMETER UserName
        Nome da conta (sem dominio).

    .PARAMETER Domain
        Dominio/maquina da conta. Quando igual a $env:COMPUTERNAME ou vazio, trata-se
        de conta local.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$UserName,
        [string]$Domain = $env:COMPUTERNAME
    )

    $isLocal = [string]::IsNullOrWhiteSpace($Domain) -or $Domain -ieq $env:COMPUTERNAME -or $Domain -eq '.'
    if (-not $isLocal) {
        return $false
    }

    $adminGroupName = (Get-CimInstanceSafe -ClassName 'Win32_Group' -Filter "LocalAccount=True AND SID='S-1-5-32-544'" |
        Select-Object -First 1 -ExpandProperty Name)
    if ([string]::IsNullOrWhiteSpace($adminGroupName)) {
        $adminGroupName = 'Administradores'
    }

    try {
        $members = @(Get-CimInstance -ClassName 'Win32_GroupUser' -Filter "GroupComponent=`"Win32_Group.Domain='$env:COMPUTERNAME',Name='$adminGroupName'`"" -ErrorAction Stop)
        foreach ($m in $members) {
            $part = [string]$m.PartComponent
            if ($part -match 'Name="?([^",]+)"?') {
                if ($Matches[1] -ieq $UserName) { return $true }
            }
        }
    }
    catch {
        Write-Verbose "Test-PrivilegedAccount: $($_.Exception.Message)"
    }

    return $false
}
