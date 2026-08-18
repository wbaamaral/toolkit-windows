#Requires -Version 5.1
<#
.SYNOPSIS
    Aplica uma cadeia de renomeacoes de diretorio na ordem raso -> profundo.

.DESCRIPTION
    Recebe a cadeia ordenada (nivel mais raso primeiro) produzida por
    Get-DiretoriosProblematicos e renomeia cada nivel na ordem correta:
    o ancestral primeiro, endereçando o diretorio filho pelo caminho ja
    atualizado (nunca pelo caminho original, que fica invalido apos o
    ancestral ser renomeado).

    Se um nivel falhar (diretorio de origem nao encontrado, destino ja
    existente, etc.), os niveis restantes da cadeia NAO sao executados
    (o estado abaixo do nivel que falhou fica imprevisivel) e sao marcados
    com status 'NaoExecutado'. A falha nunca e silenciosa: o resultado
    sempre indica sucesso/erro e o caminho final efetivamente alcancado.

.PARAMETER Cadeia
    Lista ordenada de objetos { nivel, caminho_original, nome_proposto },
    do nivel mais raso (mais proximo da raiz) para o mais profundo.

.EXAMPLE
    Invoke-DropboxCadeiaRename -Cadeia $diretorio.cadeia

.OUTPUTS
    System.Object
    Objeto com: sucesso (bool), erro (string, mensagem do primeiro nivel que
    falhou), caminho_final (string, caminho do nivel mais profundo apos a
    aplicacao -- ou o ultimo caminho alcancado em caso de falha parcial) e
    niveis (lista de objetos { nivel, caminho_original, nome_proposto,
    status, erro } com o resultado de cada nivel aplicado).
#>
function Invoke-DropboxCadeiaRename {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Cadeia
    )

    $niveisResultado = New-Object System.Collections.Generic.List[pscustomobject]
    $caminhoAcumulado = $null
    $caminhoOriginalAnterior = $null
    $sucesso = $true
    $primeiroErro = ''

    foreach ($nivelItem in ($Cadeia | Sort-Object nivel)) {
        if ($null -eq $caminhoAcumulado) {
            $origemReal = $nivelItem.caminho_original
        }
        else {
            $sufixo = ([string]$nivelItem.caminho_original).Substring($caminhoOriginalAnterior.Length)
            $origemReal = $caminhoAcumulado + $sufixo
        }
        $destino = Join-Path (Split-Path -Parent $origemReal) $nivelItem.nome_proposto

        $nivelStatus = 'Sucesso'
        $nivelErro = ''

        if ($sucesso) {
            try {
                if (-not (Test-Path -LiteralPath $origemReal -PathType Container)) {
                    throw "Diretorio nao encontrado: $origemReal"
                }
                if ($origemReal -ne $destino) {
                    if (Test-Path -LiteralPath $destino -PathType Container) {
                        throw "Diretorio de destino ja existe: $destino"
                    }
                    Rename-Item -LiteralPath $origemReal -NewName $nivelItem.nome_proposto -ErrorAction Stop
                }
            }
            catch {
                $nivelStatus = 'Erro'
                $nivelErro = $_.Exception.Message
                $sucesso = $false
                if ([string]::IsNullOrEmpty($primeiroErro)) { $primeiroErro = $nivelErro }
            }
        }
        else {
            $nivelStatus = 'NaoExecutado'
        }

        [void]$niveisResultado.Add([pscustomobject]@{
            nivel            = $nivelItem.nivel
            caminho_original = $origemReal
            nome_proposto    = $nivelItem.nome_proposto
            status           = $nivelStatus
            erro             = $nivelErro
        })

        $caminhoAcumulado = $destino
        $caminhoOriginalAnterior = $nivelItem.caminho_original
    }

    return [pscustomobject]@{
        sucesso       = $sucesso
        erro          = $primeiroErro
        caminho_final = $caminhoAcumulado
        niveis        = $niveisResultado.ToArray()
    }
}
