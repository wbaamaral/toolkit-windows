function Set-ShadowCopyStorageLimit {
    <#
    .SYNOPSIS
        Define o limite de espaco do shadow storage.
    .DESCRIPTION
        Usa vssadmin resize shadowstorage para definir o espaco maximo
        destinado a shadow copies no volume especificado.
    .PARAMETER Volume
        Volume alvo (ex: C:).
    .PARAMETER MaxSizeGB
        Espaco maximo em GB.
    .PARAMETER MaxSizePercent
        Espaco maximo como percentual do volume (ex: 10 para 10%).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Volume,

        [Parameter(ParameterSetName = 'BySize')]
        [double]$MaxSizeGB,

        [Parameter(ParameterSetName = 'ByPercent')]
        [double]$MaxSizePercent
    )

    $volPath = Resolve-VolumePath -Volume $Volume

    if ($PSCmdlet.ShouldProcess($volPath, 'Definir limite de shadow storage')) {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'BySize') {
                $sizeBytes = [long]($MaxSizeGB * 1GB)
                $result = Invoke-VssAdmin -Arguments @('resize', 'shadowstorage', "/for=${volPath}", "/maxsize=${sizeBytes}B")
            } else {
                $result = Invoke-VssAdmin -Arguments @('resize', 'shadowstorage', "/for=${volPath}", "/maxsize=${MaxSizePercent}%")
            }

            if ($result.ExitCode -ne 0) {
                throw "vssadmin resize shadowstorage falhou: $($result.Output)"
            }

            Write-Output "Limite de shadow storage em ${volPath} atualizado."
        } catch {
            Write-Error "Falha ao definir limite de shadow storage em ${volPath}: $_"
        }
    }
}
