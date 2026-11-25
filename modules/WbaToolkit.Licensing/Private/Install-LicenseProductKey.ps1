function Install-LicenseProductKey {
    <#
    .SYNOPSIS
        Instala a Product Key via SoftwareLicensingService::InstallProductKey (CIM).

    .DESCRIPTION
        Substitui 'slmgr /ipk <chave>' para que a chave nunca apareça em linha de
        comando de processo (cscript), transcript ou log (ADR 0028: logs expõem no
        máximo a Partial Product Key). Após a instalação, chama RefreshLicenseStatus,
        como o próprio slmgr faz. Nenhuma saída contém a chave completa.

    .OUTPUTS
        PSCustomObject com Success, ReturnValue, PartialKey e Message.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProductKey
    )

    $partial = ConvertTo-LicensePartialKey -ProductKey $ProductKey

    if (-not $PSCmdlet.ShouldProcess("Product Key terminada em $partial", 'Instalar via SoftwareLicensingService::InstallProductKey')) {
        return [pscustomobject]@{
            Success     = $false
            ReturnValue = $null
            PartialKey  = $partial
            Message     = 'Operacao nao executada (WhatIf ou confirmacao recusada).'
        }
    }

    try {
        $service = Get-CimInstance -Namespace 'root/cimv2' -ClassName SoftwareLicensingService -ErrorAction Stop |
            Select-Object -First 1
        $result = Invoke-CimMethod -InputObject $service -MethodName 'InstallProductKey' -Arguments @{ ProductKey = $ProductKey } -ErrorAction Stop
        $returnValue = [int]$result.ReturnValue
        if ($returnValue -eq 0) {
            try {
                $null = Invoke-CimMethod -InputObject $service -MethodName 'RefreshLicenseStatus' -ErrorAction Stop
            }
            catch {
                Write-Verbose "RefreshLicenseStatus falhou apos instalar a chave: $($_.Exception.Message)"
            }
        }
    }
    catch {
        # A mensagem do CIM nao contem a chave; o HRESULT e preservado para Resolve-LicenseError.
        $hresult = $_.Exception.HResult
        if ($_.Exception.PSObject.Properties['ErrorData'] -and $_.Exception.ErrorData -and
            $_.Exception.ErrorData.CimInstanceProperties['error_Code']) {
            $hresult = [int64]$_.Exception.ErrorData.CimInstanceProperties['error_Code'].Value
        }
        return [pscustomobject]@{
            Success     = $false
            ReturnValue = $hresult
            PartialKey  = $partial
            Message     = ('Falha ao instalar a chave (0x{0:X8}): {1}' -f ([int64]$hresult -band 0xFFFFFFFF), $_.Exception.Message)
        }
    }

    [pscustomobject]@{
        Success     = ($returnValue -eq 0)
        ReturnValue = $returnValue
        PartialKey  = $partial
        Message     = $(if ($returnValue -eq 0) { 'Chave instalada.' } else { "InstallProductKey retornou codigo $returnValue." })
    }
}
