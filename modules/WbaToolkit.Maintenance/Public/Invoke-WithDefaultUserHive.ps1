function Invoke-WithDefaultUserHive {
    <#
    .SYNOPSIS
        Monta o hive do perfil Default e executa um bloco de codigo com acesso a ele.

    .DESCRIPTION
        Carrega o arquivo NTUSER.DAT do perfil Default do Windows como chave
        temporaria em HKEY_USERS\WBA_DefaultProfile, executa o ScriptBlock
        fornecido e desmonta o hive ao final, mesmo que ocorra erro durante a
        execucao.

        O ScriptBlock recebe o nome do ponto de montagem como primeiro argumento,
        permitindo que operacoes de registro usem o caminho correto.

    .PARAMETER ScriptBlock
        Bloco de codigo a executar com o hive montado.
        O primeiro parametro recebido e o nome do ponto de montagem (sem 'HKU\').

    .EXAMPLE
        Invoke-WithDefaultUserHive -ScriptBlock {
            param($mountPoint)
            Get-Item "HKEY_USERS:\$mountPoint\Software"
        }

    .OUTPUTS
        O valor retornado pelo ScriptBlock, se houver.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    $mountName = 'WBA_DefaultProfile'
    $mountKey  = "HKU\$mountName"
    $hivePath  = Get-DefaultUserHivePath

    $loadOutput = & reg load $mountKey $hivePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao montar hive do perfil Default em '$mountKey': $loadOutput"
    }

    try {
        return (& $ScriptBlock $mountName)
    }
    finally {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        $unloadOutput = & reg unload $mountKey 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Nao foi possivel desmontar o hive '$mountKey'. Execute manualmente: reg unload $mountKey"
        }
    }
}
