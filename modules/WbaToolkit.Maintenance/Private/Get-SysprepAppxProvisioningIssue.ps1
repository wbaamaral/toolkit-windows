function Get-SysprepAppxProvisioningIssue {
    [CmdletBinding()]
    param()

    # SIDs de contas de sistema que o Windows instala pacotes automaticamente;
    # pacotes instalados apenas para esses SIDs nao bloqueiam o Sysprep.
    $sidsSistema = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')

    try {
        $provisionados = @{}
        Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object {
            $provisionados[$_.DisplayName] = $true
        }
    }
    catch {
        throw "Nao foi possivel validar pacotes Appx para Sysprep: $($_.Exception.Message). Execucao do Sysprep bloqueada por seguranca."
    }

    try {
        $instalados = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
    }
    catch {
        throw "Nao foi possivel validar pacotes Appx para Sysprep: $($_.Exception.Message). Execucao do Sysprep bloqueada por seguranca."
    }

    # Agrupa por Name para eliminar duplicatas (Get-AppxPackage retorna uma entrada por usuario).
    # Acumula todos os SIDs de usuarios reais que possuem o pacote.
    $porNome = @{}
    foreach ($pkg in $instalados) {
        if (-not $provisionados.ContainsKey($pkg.Name)) {
            $key = $pkg.Name
            if (-not $porNome.ContainsKey($key)) {
                $porNome[$key] = @{ Pkg = $pkg; Users = [System.Collections.Generic.List[string]]::new() }
            }
            if ($pkg.PackageUserInformation) {
                foreach ($ui in $pkg.PackageUserInformation) {
                    $sid = $ui.UserSecurityId
                    if ($sid -and $sidsSistema -notcontains $sid -and -not $porNome[$key].Users.Contains($sid)) {
                        $porNome[$key].Users.Add($sid)
                    }
                }
            }
        }
    }

    $bloqueadores = @()
    foreach ($entry in $porNome.Values) {
        # Reporta apenas pacotes com ao menos um usuario real instalado (nao apenas sistema).
        if ($entry.Users.Count -gt 0) {
            $pkg = $entry.Pkg
            $bloqueadores += [pscustomobject]@{
                Name            = $pkg.Name
                PackageFullName = $pkg.PackageFullName
                Version         = $pkg.Version
                Architecture    = $pkg.Architecture
                Publisher       = $pkg.Publisher
                Users           = $entry.Users.ToArray()
                Reason          = 'InstalledForUserButNotProvisioned'
                Severity        = 'Blocker'
            }
        }
    }

    return $bloqueadores
}
