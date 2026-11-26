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
        [object[]]$Cadeia,

        # Mapa compartilhado entre cadeias (caminho original -> caminho atual) dos
        # diretorios ja renomeados. Cadeias de diretorios diferentes podem conter o
        # mesmo ancestral: sem o mapa, a segunda cadeia procurava o ancestral pelo
        # caminho original (ja renomeado) e falhava. O mapa e atualizado aqui.
        [System.Collections.IDictionary]$RenomeadosMap
    )

    if ($null -eq $RenomeadosMap) { $RenomeadosMap = @{} }

    # Traduz um caminho original para o caminho atual usando o prefixo renomeado mais longo.
    $traduzir = {
        param([string]$CaminhoOriginal)
        $melhor = $null
        foreach ($chave in @($RenomeadosMap.Keys)) {
            $k = [string]$chave
            if ($CaminhoOriginal.Equals($k, [System.StringComparison]::OrdinalIgnoreCase) -or
                $CaminhoOriginal.StartsWith($k + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($null -eq $melhor -or $k.Length -gt $melhor.Length) { $melhor = $k }
            }
        }
        if ($null -eq $melhor) { return $CaminhoOriginal }
        return [string]$RenomeadosMap[$melhor] + $CaminhoOriginal.Substring($melhor.Length)
    }

    $niveisResultado = New-Object System.Collections.Generic.List[pscustomobject]
    $caminhoAcumulado = $null
    $sucesso = $true
    $primeiroErro = ''

    foreach ($nivelItem in ($Cadeia | Sort-Object nivel)) {
        $caminhoOriginal = [string]$nivelItem.caminho_original
        $jaRenomeado = $RenomeadosMap.Contains($caminhoOriginal)

        if ($jaRenomeado) {
            # Ancestral comum ja renomeado por outra cadeia: nada a fazer neste nivel.
            $origemReal = $caminhoOriginal
            $destino = [string]$RenomeadosMap[$caminhoOriginal]
        }
        else {
            $origemReal = & $traduzir $caminhoOriginal
            $destino = Join-Path (Split-Path -Parent $origemReal) $nivelItem.nome_proposto
        }

        $nivelStatus = 'Sucesso'
        $nivelErro = ''

        if (-not $sucesso) {
            $nivelStatus = 'NaoExecutado'
        }
        elseif ($jaRenomeado) {
            if ((Split-Path -Leaf $destino) -ne $nivelItem.nome_proposto) {
                $nivelStatus = 'Erro'
                $nivelErro = "Diretorio ja renomeado por outra cadeia para '$(Split-Path -Leaf $destino)', diferente do proposto '$($nivelItem.nome_proposto)': $caminhoOriginal"
                $sucesso = $false
                $primeiroErro = $nivelErro
            }
            elseif (-not (Test-Path -LiteralPath $destino -PathType Container)) {
                $nivelStatus = 'Erro'
                $nivelErro = "Diretorio renomeado anteriormente nao encontrado: $destino"
                $sucesso = $false
                $primeiroErro = $nivelErro
            }
            else {
                $nivelStatus = 'JaAplicado'
            }
        }
        else {
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
                $RenomeadosMap[$caminhoOriginal] = $destino
            }
            catch {
                $nivelStatus = 'Erro'
                $nivelErro = $_.Exception.Message
                $sucesso = $false
                if ([string]::IsNullOrEmpty($primeiroErro)) { $primeiroErro = $nivelErro }
            }
        }

        [void]$niveisResultado.Add([pscustomobject]@{
            nivel            = $nivelItem.nivel
            caminho_original = $origemReal
            nome_proposto    = $nivelItem.nome_proposto
            status           = $nivelStatus
            erro             = $nivelErro
        })

        $caminhoAcumulado = $destino
    }

    return [pscustomobject]@{
        sucesso       = $sucesso
        erro          = $primeiroErro
        caminho_final = $caminhoAcumulado
        niveis        = $niveisResultado.ToArray()
    }
}
