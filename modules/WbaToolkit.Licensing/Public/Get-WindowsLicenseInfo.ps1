function Get-WindowsLicenseInfo {
    <#
    .SYNOPSIS
        Diagnóstico da licença Windows consolidando CIM + slmgr + HWID (RF-01).
    .DESCRIPTION
        Consulta SoftwareLicensingProduct/SoftwareLicensingService via CIM,
        executa Invoke-Slmgr /dli, /dlv e /xpr, e computa o contexto de hardware
        via Get-LicenseHardwareContext (RF-01.b). Somente leitura.
    .PARAMETER BaselinePath
        Caminho do arquivo hwid-baseline.json. Se omitido, nenhum baseline é carregado.
    .PARAMETER SkipSlmgr
        Não executa slmgr (útil em testes ou quando slmgr está indisponível).
    .EXAMPLE
        Get-WindowsLicenseInfo
    #>
    [CmdletBinding()]
    param(
        [string]$BaselinePath,
        [switch]$SkipSlmgr
    )

    $product = @(Get-SoftwareLicensingProduct | Select-Object -First 1)
    $service = @(Get-SoftwareLicensingService | Select-Object -First 1)
    if ($product.Count -eq 0) { $product = $null }
    if ($service.Count -eq 0) { $service = $null }

    $dli = $null; $dlv = $null; $xpr = $null
    if (-not $SkipSlmgr) {
        $dli = Invoke-Slmgr -ArgumentList @('/dli')
        $dlv = Invoke-Slmgr -ArgumentList @('/dlv')
        $xpr = Invoke-Slmgr -ArgumentList @('/xpr')
    }

    $hardware = Get-LicenseHardwareContext -BaselinePath $BaselinePath

    return ConvertTo-LicenseInfoObject -Product $product -Service $service `
        -SlmgrDli $dli -SlmgrDlv $dlv -SlmgrXpr $xpr -Hardware $hardware
}
