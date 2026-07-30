function New-ShadowCopy {
    <#
    .SYNOPSIS
        Cria um novo shadow copy (snapshot de volume).
    .DESCRIPTION
        Cria um shadow copy do volume especificado usando o WMI Win32_ShadowCopy.
    .PARAMETER Volume
        Volume alvo (ex: C:). Padrao: C:.
    .OUTPUTS
        PSCustomObject com ShadowCopyId, Volume, CreatedAt.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Volume = 'C:'
    )

    $volPath = Resolve-VolumePath -Volume $Volume

    if ($PSCmdlet.ShouldProcess($volPath, 'Criar Shadow Copy')) {
        try {
            $result = Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{
                Volume = $volPath
            } -ErrorAction Stop

            if ($result.ReturnValue -ne 0) {
                throw "Win32_ShadowCopy.Create retornou ReturnValue=$($result.ReturnValue)"
            }

            Start-Sleep -Seconds 2

            $newShadow = Get-CimInstance Win32_ShadowCopy |
                Where-Object { $_.ID -eq $result.ShadowID } |
                Select-Object -First 1

            [pscustomobject]@{
                ShadowCopyId = $result.ShadowID
                Volume       = $volPath
                DeviceObject = $newShadow.DeviceObject
                CreatedAt    = $newShadow.InstallDate
                State        = $newShadow.State
            }
        } catch {
            Write-Error "Falha ao criar shadow copy em ${volPath}: $_"
        }
    }
}
