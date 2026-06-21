function Get-SysprepAppxProvisioningIssue {
    [CmdletBinding()]
    param()

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

    $bloqueadores = @()
    foreach ($pkg in $instalados) {
        if (-not $provisionados.ContainsKey($pkg.Name)) {
            $usuarios = @($pkg.PackageUserInformation | ForEach-Object { $_.UserSecurityId })
            $bloqueadores += [pscustomobject]@{
                Name            = $pkg.Name
                PackageFullName = $pkg.PackageFullName
                Version         = $pkg.Version
                Architecture    = $pkg.Architecture
                Publisher       = $pkg.Publisher
                Users           = $usuarios
                Reason          = 'InstalledForUserButNotProvisioned'
                Severity        = 'Blocker'
            }
        }
    }

    return $bloqueadores
}
