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

    $appxSvc = Get-Service -Name 'AppXSvc' -ErrorAction SilentlyContinue
    if (-not $appxSvc) {
        throw 'Servico AppXSvc nao encontrado. Nao e possivel validar pacotes Appx. Execucao do Sysprep bloqueada por seguranca.'
    }
    if ($appxSvc.Status -ne 'Running') {
        throw "Servico AppXSvc nao esta em execucao (Status: $($appxSvc.Status)). Inicie o servico e tente novamente. Execucao do Sysprep bloqueada por seguranca."
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

    function ConvertTo-PackageVersion {
        param($Value)
        $parsed = $null
        if ($null -ne $Value -and [version]::TryParse([string]$Value, [ref]$parsed)) {
            return $parsed
        }
        return $null
    }

    # Agrupa por Name para eliminar duplicatas (Get-AppxPackage retorna uma entrada por usuario).
    # Acumula todos os SIDs de usuarios reais que possuem o pacote em estado Installed.
    $porNome = @{}
    foreach ($pkg in $instalados) {
        $key = $pkg.Name
        $motivoBase = 'InstalledForUserButNotProvisioned'

        if ($provisionados.ContainsKey($pkg.Name)) {
            # App da imagem atualizado pela Store para um usuario: a versao nova nao esta
            # provisionada e o sysprep falha do mesmo jeito (BCK-072). A chave passa a ser o
            # PackageFullName, para a remocao mirar so a versao atualizada.
            $versaoInstalada    = ConvertTo-PackageVersion $pkg.Version
            $versaoProvProp     = $provisionados[$pkg.Name].PSObject.Properties['Version']
            $versaoProvisionada = if ($versaoProvProp) { ConvertTo-PackageVersion $versaoProvProp.Value } else { $null }
            if (-not $versaoInstalada -or -not $versaoProvisionada -or $versaoInstalada -le $versaoProvisionada) {
                continue
            }
            $key = [string]$pkg.PackageFullName
            $motivoBase = 'UpdatedForUserButProvisionedOlder'
        }

        if (-not $porNome.ContainsKey($key)) {
            $porNome[$key] = @{ Pkg = $pkg; Users = [System.Collections.Generic.List[string]]::new(); Reason = $motivoBase }
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

        $isLanguagePack = $pkg.Name -like 'Microsoft.LanguageExperiencePack*'

        $severity = 'Blocker'
        $reason   = $entry.Reason

        if ($isFramework -or $isResourcePackage -or $isNonRemovable -or $isSystemApp) {
            if ($isLanguagePack) {
                # Language packs sao resource packages mas bloqueiam o Sysprep mesmo assim.
                $reason = 'LanguagePackInstalledForUserButNotProvisioned'
            } else {
                $severity = 'Warning'
                $reason   = 'SystemFrameworkResourceOrNonRemovableNotProvisioned'
            }
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
