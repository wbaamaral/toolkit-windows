function Get-SshUserProfilePath {
    # Resolve a pasta de perfil de um usuario pelo SID (ADR 0034). Perfis de dominio costumam ficar em
    # C:\Users\usuario.DOMINIO e a raiz dos perfis pode nao ser C:\Users, entao montar
    # "C:\Users\<nome>" aponta para a pasta errada.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName
    )

    $cleanUser = ($UserName -split '\\')[-1]
    if ($cleanUser -eq $env:USERNAME -and $env:USERPROFILE) {
        return $env:USERPROFILE
    }

    try {
        $account = New-Object System.Security.Principal.NTAccount($UserName)
        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
        $profileKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
        $imagePath = (Get-ItemProperty -LiteralPath $profileKey -Name 'ProfileImagePath' -ErrorAction Stop).ProfileImagePath
        if ($imagePath) {
            return [System.Environment]::ExpandEnvironmentVariables($imagePath)
        }
    }
    catch {
        Write-Verbose "Perfil de '$UserName' nao encontrado pelo SID: $($_.Exception.Message)"
    }

    # Perfil ainda nao criado (usuario nunca entrou): usa a mesma raiz de perfis do usuario atual.
    $profilesRoot = if ($env:USERPROFILE) { Split-Path -Parent $env:USERPROFILE } else { 'C:\Users' }
    return (Join-Path $profilesRoot $cleanUser)
}
