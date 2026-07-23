function ConvertTo-LicenseInfoObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [pscustomobject]$Product,
        [Parameter(Mandatory = $false)] [pscustomobject]$Service,
        [Parameter(Mandatory = $false)] [pscustomobject]$SlmgrDli,
        [Parameter(Mandatory = $false)] [pscustomobject]$SlmgrDlv,
        [Parameter(Mandatory = $false)] [pscustomobject]$SlmgrXpr,
        [Parameter(Mandatory = $false)] [pscustomobject]$Hardware
    )

    $description = [string]$Product.Description
    $name = [string]$Product.Name
    $channelText = "$name $description"
    $channel = switch -Regex ($channelText) {
        'OEM(_DM)?|OEM' { 'OEM'; break }
        'RETAIL channel' { 'Retail'; break }
        'VOLUME_KMSCLIENT' { 'KMS'; break }
        'VOLUME_MAK' { 'MAK'; break }
        'GVLK' { 'GVLK'; break }
        'AVMA_' { 'AVMA'; break }
        default { 'Desconhecido' }
    }
    $statusMap = @{ 1 = 'Licensed'; 2 = 'OOBGrace'; 3 = 'OOBGraceExpired'; 4 = 'NonGenuineGrace'; 5 = 'Notification'; 6 = 'ExtendedGrace' }
    $statusCode = [int]$Product.LicenseStatus
    $partial = [string]$Product.PartialProductKey
    if ($partial.Length -gt 5) { $partial = $partial.Substring($partial.Length - 5) }

    [pscustomobject]@{
        ColetadoEm = (Get-Date).ToString('o')
        Windows = [pscustomobject]@{ Edicao = $Product.Name; Versao = $Product.Version; Build = $Product.Version; Arquitetura = $env:PROCESSOR_ARCHITECTURE }
        Licenca = [pscustomobject]@{
            Canal = $channel; CanalDetalhe = $description; Status = $(if ($statusMap.ContainsKey($statusCode)) { $statusMap[$statusCode] } else { 'Unknown' })
            StatusCodigo = $statusCode; PartialProductKey = $partial; ProductId = $Product.ID; InstallationId = $Product.InstallationID
            ActivationId = $Product.ID; ApplicationId = $Product.ApplicationId; DigitalLicense = ($channel -eq 'OEM' -or $channel -eq 'Retail')
        }
        Kms = [pscustomobject]@{ Servidor = $Service.KeyManagementServiceMachine; Porta = $Service.KeyManagementServicePort; ClienteKms = ($channel -eq 'KMS') }
        Rearm = [pscustomobject]@{ Restante = $Service.RemainingWindowsReArmCount }
        Hardware = $Hardware
        Slmgr = [pscustomobject]@{ Dli = $SlmgrDli; Dlv = $SlmgrDlv; Xpr = $SlmgrXpr }
    }
}
