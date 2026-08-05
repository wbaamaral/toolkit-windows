function Set-ToolkitCertificateDesiredState {
    <#
    .SYNOPSIS
        Etapa certificates.install — instala os certificados declarados e ausentes.

    .DESCRIPTION
        Fonte por arquivo local (source.filePath, resolvido relativo a Work\<deploymentId>
        quando nao absoluto) ou conteudo publico em base64 (source.contentBase64). PFX exige
        source.pfxPasswordSecretRef (nunca senha em texto claro); a chave privada e importada
        nao-exportavel. Certificado publico (.cer) usa Import-Certificate. Nenhuma senha ou
        bytes de PFX entram no resultado da etapa.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $workDir = Join-Path $Context.Paths.Work $Context.DeploymentId
    $installed = @()

    foreach ($entry in @($Context.Config.certificates)) {
        $store = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'store') -and $entry.store) { [string]$entry.store } else { 'LocalMachine\My' }
        if (Find-ToolkitProvisioningCertificate -Thumbprint ([string]$entry.thumbprint) -Store $store) {
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($entry.name, "Instalar certificado em Cert:\$store")) {
            continue
        }

        $source = $entry.source
        $tempFile = $null
        try {
            if ((Test-ToolkitPropertyPresent -InputObject $source -Name 'contentBase64') -and $source.contentBase64) {
                $tempFile = Join-Path $Context.Paths.Secrets "$([guid]::NewGuid().ToString('N')).cer"
                [System.IO.File]::WriteAllBytes($tempFile, [Convert]::FromBase64String([string]$source.contentBase64))
                $sourcePath = $tempFile
            }
            else {
                $sourcePath = [string]$source.filePath
                if (-not [System.IO.Path]::IsPathRooted($sourcePath)) {
                    $sourcePath = Join-Path $workDir $sourcePath
                }
            }

            if ((Test-ToolkitPropertyPresent -InputObject $source -Name 'pfxPasswordSecretRef') -and $source.pfxPasswordSecretRef) {
                $pfxPassword = Resolve-ToolkitProvisioningSecret -SecretRef ([string]$source.pfxPasswordSecretRef) -Paths $Context.Paths
                try {
                    Import-PfxCertificate -FilePath $sourcePath -CertStoreLocation "Cert:\$store" -Password $pfxPassword -Exportable:$false -ErrorAction Stop | Out-Null
                }
                finally {
                    $pfxPassword = $null
                }
            }
            else {
                Import-Certificate -FilePath $sourcePath -CertStoreLocation "Cert:\$store" -ErrorAction Stop | Out-Null
            }

            $installed += $entry.name
        }
        finally {
            if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Certificados instalados: $($installed -join ', ')."
        Evidence       = [pscustomobject]@{ InstalledCertificates = $installed }
    }
}
