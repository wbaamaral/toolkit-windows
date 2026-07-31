function Remove-ShadowCopy {
    <#
    .SYNOPSIS
        Remove shadow copies.
    .DESCRIPTION
        Remove shadow copies individuais, todas de um volume, ou todas do sistema.
    .PARAMETER ShadowCopyId
        ID do shadow copy especifico a remover.
    .PARAMETER Volume
        Remove todos os shadow copies do volume.
    .PARAMETER All
        Remove todos os shadow copies de todos os volumes.
    .PARAMETER Oldest
        Remove o shadow copy mais antigo.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$ShadowCopyId,

        [Parameter(ParameterSetName = 'ByVolume')]
        [string]$Volume,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(ParameterSetName = 'Oldest')]
        [switch]$Oldest
    )

    if ($PSCmdlet.ShouldProcess('Shadow Copy', 'Remover')) {
        try {
            switch ($PSCmdlet.ParameterSetName) {
                'ById' {
                    $target = Get-CimInstance Win32_ShadowCopy | Where-Object { $_.ID -eq $ShadowCopyId }
                    if (-not $target) { throw "Shadow copy '$ShadowCopyId' nao encontrado." }
                    $target | Remove-CimInstance -ErrorAction Stop
                    Write-Output "Shadow copy '$ShadowCopyId' removido."
                }
                'ByVolume' {
                    $volPath = Resolve-VolumePath -Volume $Volume
                    $targets = Get-CimInstance Win32_ShadowCopy | Where-Object { $_.Volume -like "$volPath*" }
                    if (-not $targets) { Write-Warning "Nenhum shadow copy encontrado em ${volPath}."; return }
                    $targets | Remove-CimInstance -ErrorAction Stop
                    Write-Output "$($targets.Count) shadow copy(s) removido(s) de ${volPath}."
                }
                'All' {
                    $targets = Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue
                    if (-not $targets) { Write-Warning "Nenhum shadow copy encontrado."; return }
                    $targets | Remove-CimInstance -ErrorAction Stop
                    Write-Output "$($targets.Count) shadow copy(s) removido(s) de todos os volumes."
                }
                'Oldest' {
                    $oldest = Get-CimInstance Win32_ShadowCopy |
                        Sort-Object InstallDate |
                        Select-Object -First 1
                    if (-not $oldest) { Write-Warning "Nenhum shadow copy encontrado."; return }
                    $oldest | Remove-CimInstance -ErrorAction Stop
                    Write-Output "Shadow copy mais antigo ($($oldest.InstallDate)) removido."
                }
            }
        } catch {
            Write-Error "Falha ao remover shadow copy: $_"
        }
    }
}
