function Test-SshUserIsAdmin {
    <#
    .SYNOPSIS
        Verifica se o usuario informado pertence ao grupo local de Administradores.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UserName
    )

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $UserName = $env:USERNAME
    }

    $cleanUser = ($UserName -split '\\')[-1]

    # Se for o processo atual, checar o token de seguranca
    if ($cleanUser -eq $env:USERNAME) {
        try {
            $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]$currentIdentity
            if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                return $true
            }
        }
        catch {
            Write-Verbose "Test-SshUserIsAdmin: Falha ao verificar papel de administrador atual: $($_.Exception.Message)"
        }
    }

    # Verificar associacao ao grupo Administrators (SID S-1-5-32-544)
    try {
        if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
            $adminGroup = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue
            if ($adminGroup) {
                $members = Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue
                foreach ($m in $members) {
                    $mName = ($m.Name -split '\\')[-1]
                    if ($mName -eq $cleanUser) {
                        return $true
                    }
                }
            }
        }
    }
    catch {
        Write-Verbose "Test-SshUserIsAdmin: Falha ao consultar Get-LocalGroupMember: $($_.Exception.Message)"
    }

    return $false
}
