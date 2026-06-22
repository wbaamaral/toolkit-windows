function Get-SysprepAppxProvisioningIssue {
    [CmdletBinding()]
    param(
        [switch]$IncludeWarnings
    )

    function Test-IsSystemSid {
        param([string]$Sid)

        if ([string]::IsNullOrWhiteSpace($Sid)) {
            return $true
        }

        return (
            $Sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20') -or
            $Sid -like 'S-1-5-80-*' -or
            $Sid -like 'S-1-15-*'
        )
    }

    function Get-ObjectBoolProperty {
        param(
            [Parameter(Mandatory = $true)]$InputObject,
            [Parameter(Mandatory = $true)][string]$Name
        )

        $prop = $InputObject.PSObject.Properties[$Name]
        if (-not $prop) {
            return $false
        }

        return [bool]$prop.Value
    }

    try {
        $provisionados = @{}
        Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object {
            $provisionados[$_.DisplayName] = $_
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
    # Acumula todos os SIDs de usuarios reais que possuem o pacote em estado Installed.
    $porNome = @{}
    foreach ($pkg in $instalados) {
        if ($provisionados.ContainsKey($pkg.Name)) {
            continue
        }

        $key = $pkg.Name
        if (-not $porNome.ContainsKey($key)) {
            $porNome[$key] = @{ Pkg = $pkg; Users = [System.Collections.Generic.List[string]]::new() }
        }

        if (-not $pkg.PackageUserInformation) {
            continue
        }

        foreach ($ui in $pkg.PackageUserInformation) {
            $sid = [string]$ui.UserSecurityId
            if (Test-IsSystemSid -Sid $sid) {
                continue
            }

            # Quando o campo existir, considera bloqueante apenas o estado Installed.
            # Estados Staged/Paused/Unknown aparecem em alguns cenarios e nao indicam,
            # sozinhos, pacote ativo no perfil do usuario.
            $estadoProp = $ui.PSObject.Properties['PackageUserInstallState']
            if ($estadoProp -and $estadoProp.Value -and $estadoProp.Value.ToString() -ne 'Installed') {
                continue
            }

            if (-not $porNome[$key].Users.Contains($sid)) {
                $porNome[$key].Users.Add($sid)
            }
        }
    }

    $issues = @()
    foreach ($entry in $porNome.Values) {
        # Reporta apenas pacotes com ao menos um usuario real instalado (nao apenas sistema).
        if ($entry.Users.Count -eq 0) {
            continue
        }

        $pkg = $entry.Pkg

        $isFramework       = Get-ObjectBoolProperty -InputObject $pkg -Name 'IsFramework'
        $isResourcePackage = Get-ObjectBoolProperty -InputObject $pkg -Name 'IsResourcePackage'
        $isNonRemovable   = Get-ObjectBoolProperty -InputObject $pkg -Name 'NonRemovable'
        $isSystemApp       = $false
        if ($pkg.PSObject.Properties['InstallLocation'] -and $pkg.InstallLocation) {
            $systemAppsRoot = Join-Path $env:SystemRoot 'SystemApps'
            $isSystemApp = $pkg.InstallLocation.StartsWith($systemAppsRoot, [System.StringComparison]::OrdinalIgnoreCase)
        }

        $severity = 'Blocker'
        $reason   = 'InstalledForUserButNotProvisioned'

        if ($isFramework -or $isResourcePackage -or $isNonRemovable -or $isSystemApp) {
            $severity = 'Warning'
            $reason   = 'SystemFrameworkResourceOrNonRemovableNotProvisioned'
        }

        if ($severity -eq 'Warning' -and -not $IncludeWarnings) {
            continue
        }

        $issues += [pscustomobject]@{
            Name              = $pkg.Name
            PackageFullName   = $pkg.PackageFullName
            Version           = $pkg.Version
            Architecture      = $pkg.Architecture
            Publisher         = $pkg.Publisher
            Users             = $entry.Users.ToArray()
            Reason            = $reason
            Severity          = $severity
            IsFramework       = $isFramework
            IsResourcePackage = $isResourcePackage
            NonRemovable      = $isNonRemovable
            IsSystemApp       = $isSystemApp
        }
    }

    return $issues
}
