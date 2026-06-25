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

    # Limpa montagem stale de uma execucao anterior que nao desmontou: senao o
    # 'reg load' falha e o hive fica preso, quebrando logon/criacao de perfis.
    if (Test-Path -LiteralPath "Registry::HKEY_USERS\$mountName") {
        Write-Warn "Montagem stale detectada em '$mountKey' (execucao anterior). Desmontando antes de prosseguir."
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        & reg unload $mountKey 2>&1 | Out-Null
    }

    # Mesmo comportamento de reg import: reg.exe PT-BR escreve sucesso em stderr.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $loadOutput = & reg load $mountKey $hivePath 2>&1
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao montar hive do perfil Default em '$mountKey': $($loadOutput -join ' ')"
    }

    $resultado  = $null
    $erroScript = $null
    try {
        $resultado = & $ScriptBlock $mountName
    }
    catch {
        $erroScript = $_
    }

    # Desmonta com retry: handles do registro podem demorar a liberar; o GC entre
    # tentativas libera RegistryKey finalizaveis que mantem o hive aberto.
    $desmontado   = $false
    $unloadOutput = ''
    for ($tentativa = 1; $tentativa -le 3; $tentativa++) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        $prevEAP2 = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $unloadOutput = & reg unload $mountKey 2>&1
        $ErrorActionPreference = $prevEAP2
        if ($LASTEXITCODE -eq 0) { $desmontado = $true; break }
        Start-Sleep -Milliseconds 400
    }

    # Erro do ScriptBlock tem prioridade — nao mascarar a causa original.
    if ($erroScript) { throw $erroScript }

    if (-not $desmontado) {
        throw ("Nao foi possivel desmontar o hive '$mountKey' apos 3 tentativas: $unloadOutput. " +
            "O hive segue montado — execute manualmente: reg unload $mountKey")
    }

    return $resultado
}
