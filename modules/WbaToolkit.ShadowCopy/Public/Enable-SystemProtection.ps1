function Enable-SystemProtection {
    <#
    .SYNOPSIS
        Habilita a Protecao do Sistema em um volume.
    .DESCRIPTION
        Ativa a Protecao do Sistema (System Restore) para o volume especificado.
    .PARAMETER Volume
        Volume alvo (ex: C:). Padrao: C:.
    .PARAMETER MaxAllocationGB
        Espaco maximo em GB para shadow copies. Se omitido, usa o valor atual do sistema.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Volume = 'C:',
        [double]$MaxAllocationGB
    )

    $volPath = Resolve-VolumePath -Volume $Volume

    if ($PSCmdlet.ShouldProcess($volPath, 'Habilitar Protecao do Sistema')) {
        try {
            Enable-ComputerRestore -Drive $volPath -ErrorAction Stop
            if ($MaxAllocationGB -gt 0) {
                $sizeBytes = [long]($MaxAllocationGB * 1GB)
                $null = Invoke-VssAdmin -Arguments @('resize', 'shadowstorage', "/for=${volPath}", "/maxsize=${sizeBytes}B")
            }
            Write-Output "Protecao do Sistema habilitada em ${volPath}."
        } catch {
            Write-Error "Falha ao habilitar Protecao do Sistema em ${volPath}: $_"
        }
    }
}
