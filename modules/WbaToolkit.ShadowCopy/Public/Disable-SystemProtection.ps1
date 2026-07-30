function Disable-SystemProtection {
    <#
    .SYNOPSIS
        Desabilita a Protecao do Sistema em um volume.
    .DESCRIPTION
        Desativa a Protecao do Sistema (System Restore) para o volume especificado.
        ATENCAO: Isso remove todos os shadow copies e restore points existentes.
    .PARAMETER Volume
        Volume alvo (ex: C:). Padrao: C:.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Volume = 'C:'
    )

    $volPath = Resolve-VolumePath -Volume $Volume

    if ($PSCmdlet.ShouldProcess($volPath, 'Desabilitar Protecao do Sistema')) {
        try {
            Disable-ComputerRestore -Drive $volPath -ErrorAction Stop
            Write-Output "Protecao do Sistema desabilitada em ${volPath}."
            Write-Warning "Todos os shadow copies e restore points deste volume foram removidos."
        } catch {
            Write-Error "Falha ao desabilitar Protecao do Sistema em ${volPath}: $_"
        }
    }
}
