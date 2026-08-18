#Requires -Version 5.1
<#
.SYNOPSIS
    Agrupa arquivos problematicos por diretorio pai e propoe uma cadeia de
    renomeacoes ate que o caminho completo resultante caiba no limite
    configurado.

.DESCRIPTION
    Para cada diretorio pai com arquivos problematicos, propoe um nome mais
    curto para o nivel mais profundo (reaproveitando Get-SafeFileName) e
    recalcula o comprimento do caminho completo resultante para todos os
    arquivos afetados (nao apenas o nome do diretorio isolado).

    Se, apos a proposta no nivel mais profundo, algum arquivo ainda
    ultrapassar o limite (descontada a margem de seguranca), a funcao sobe
    para o diretorio ancestral e repete a proposta de encurtamento nesse
    nivel -- ate caber ou ate atingir -CaminhoRaiz, que nunca e renomeada.

    A cadeia retornada por diretorio (propriedade 'cadeia') fica ordenada do
    nivel mais raso (mais proximo da raiz) para o mais profundo, pronta para
    ser aplicada nessa ordem por -Modo Aplicar.

.PARAMETER Arquivos
    Lista de arquivos problematicos (objetos com propriedades Caminho e
    Nome), no formato gerado por diagnosticar-dropbox.ps1 -ExportarJson.

.PARAMETER CaminhoRaiz
    Raiz protegida (ex.: pasta raiz do Dropbox analisada). A cadeia de
    encurtamento nunca sobe alem deste diretorio -- ele proprio nunca e
    proposto para renomeacao.

.PARAMETER LimiteCaminho
    Comprimento maximo de caminho tolerado. Padrao: 260 (limite classico do
    Windows sem long paths habilitado).

.PARAMETER MargemSeguranca
    Quantidade de caracteres reservados como margem de seguranca, subtraida
    de -LimiteCaminho para formar o alvo real de encurtamento. Padrao: 10.

.EXAMPLE
    Get-DiretoriosProblematicos -Arquivos $jsonData.arquivos_problematicos -CaminhoRaiz 'C:\Dropbox (Empresa)'

    Agrupa os arquivos problematicos do diagnostico e propoe a cadeia de
    encurtamento necessaria para cada diretorio pai.

.OUTPUTS
    System.Object[]
    Um objeto por diretorio pai, com as propriedades:
    id, diretorio, nome_original, nome_proposto (nivel mais profundo,
    compatibilidade com versao anterior), caminho_original,
    caminho_proposto (caminho final do nivel mais profundo apos aplicar toda
    a cadeia), total_arquivos, maior_sufixo (comprimento do maior sufixo
    relativo -- arquivo dentro do diretorio -- observado no grupo),
    problemas, problema_pred, selecionado, ja_valido, resolvido,
    atingiu_raiz e cadeia (lista ordenada de objetos
    { nivel, caminho_original, nome_proposto } do mais raso ao mais
    profundo).
#>
function Get-DiretoriosProblematicos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Arquivos,

        [Parameter(Mandatory = $true)]
        [string]$CaminhoRaiz,

        [Parameter(Mandatory = $false)]
        [int]$LimiteCaminho = 260,

        [Parameter(Mandatory = $false)]
        [int]$MargemSeguranca = 10
    )

    $caminhoRaizNormalizado = $CaminhoRaiz.TrimEnd('\', '/')
    $alvo = $LimiteCaminho - $MargemSeguranca

    # Agrupar por diretorio pai
    $grupos = @{}
    foreach ($arq in $Arquivos) {
        $dir = Split-Path -Parent ([string]$arq.Caminho)
        if (-not $grupos.ContainsKey($dir)) {
            $grupos[$dir] = New-Object System.Collections.Generic.List[object]
        }
        [void]$grupos[$dir].Add($arq)
    }

    $diretorios = New-Object System.Collections.Generic.List[object]
    $id = 1

    foreach ($dir in ($grupos.Keys | Sort-Object)) {
        $itens = $grupos[$dir]
        $dirName = Split-Path -Leaf $dir

        # --- Identificar problemas predominantes (mesma logica anterior) ---
        $problemas = @{}
        $maiorSufixo = 0
        foreach ($arq in $itens) {
            $caminhoArq = [string]$arq.Caminho
            $nome = [string]$arq.Nome
            if ([string]::IsNullOrWhiteSpace($nome)) { $nome = Split-Path -Leaf $caminhoArq }

            $sufixo = $caminhoArq.Substring($dir.Length)
            if ($sufixo.Length -gt $maiorSufixo) { $maiorSufixo = $sufixo.Length }

            if ($caminhoArq.Length -gt $LimiteCaminho) {
                if (-not $problemas.ContainsKey('Caminho > 260')) { $problemas['Caminho > 260'] = 0 }; $problemas['Caminho > 260']++
            }
            if ($nome -match '[<>:"/\\|?*]') {
                if (-not $problemas.ContainsKey('Caracteres invalidos')) { $problemas['Caracteres invalidos'] = 0 }; $problemas['Caracteres invalidos']++
            }
            $reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
            $dotIdx = $nome.LastIndexOf('.')
            $baseName = if ($dotIdx -gt 0) { $nome.Substring(0, $dotIdx) } else { $nome }
            if ($reservedNames -contains $baseName.ToUpperInvariant()) {
                if (-not $problemas.ContainsKey('Nome reservado')) { $problemas['Nome reservado'] = 0 }; $problemas['Nome reservado']++
            }
            if ($nome.EndsWith('.') -or $nome.EndsWith(' ')) {
                if (-not $problemas.ContainsKey('Termina em ponto/espaco')) { $problemas['Termina em ponto/espaco'] = 0 }; $problemas['Termina em ponto/espaco']++
            }
        }

        $problemaPredominante = ($problemas.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        if ([string]::IsNullOrWhiteSpace($problemaPredominante)) { $problemaPredominante = 'Outro' }

        # --- Construcao da cadeia de encurtamento (mais profundo -> mais raso) ---
        $nomePropostoNivel0 = Get-SafeFileName -Name $dirName
        $cadeiaProfundaParaRasa = New-Object System.Collections.Generic.List[object]
        [void]$cadeiaProfundaParaRasa.Add([pscustomobject]@{ caminho_original = $dir; nome_proposto = $nomePropostoNivel0 })

        $atualDir = $dir
        $resolvido = $false
        $atingiuRaiz = $false
        $novoCaminhoDirFinal = $null

        while ($true) {
            # Cascatear os nomes propostos (do mais raso para o mais profundo)
            # para obter o caminho final do diretorio mais profundo.
            $topoAtual = $cadeiaProfundaParaRasa[$cadeiaProfundaParaRasa.Count - 1]
            $novoCaminhoDir = Split-Path -Parent $topoAtual.caminho_original
            for ($i = $cadeiaProfundaParaRasa.Count - 1; $i -ge 0; $i--) {
                $novoCaminhoDir = Join-Path $novoCaminhoDir $cadeiaProfundaParaRasa[$i].nome_proposto
            }
            $novoCaminhoDirFinal = $novoCaminhoDir

            $maxLen = $novoCaminhoDir.Length + $maiorSufixo

            if ($maxLen -le $alvo) { $resolvido = $true; break }

            if ($atualDir -ieq $caminhoRaizNormalizado) { $atingiuRaiz = $true; break }

            $pai = Split-Path -Parent $atualDir
            if ([string]::IsNullOrWhiteSpace($pai) -or $pai.Length -lt $caminhoRaizNormalizado.Length -or $pai -ieq $caminhoRaizNormalizado) {
                $atingiuRaiz = $true; break
            }

            $nomeAncestral = Split-Path -Leaf $pai
            if ([string]::IsNullOrWhiteSpace($nomeAncestral)) { $atingiuRaiz = $true; break }

            $excesso = $maxLen - $alvo
            $desiredMax = [Math]::Max(11, ($nomeAncestral.Length - $excesso + 1))
            $nomeAncestralProposto = Get-SafeFileName -Name $nomeAncestral -MaxLength $desiredMax

            [void]$cadeiaProfundaParaRasa.Add([pscustomobject]@{ caminho_original = $pai; nome_proposto = $nomeAncestralProposto })
            $atualDir = $pai
        }

        # Inverter para ordem raso -> profundo e numerar os niveis
        $cadeia = New-Object System.Collections.Generic.List[object]
        $nivel = 1
        for ($i = $cadeiaProfundaParaRasa.Count - 1; $i -ge 0; $i--) {
            $item = $cadeiaProfundaParaRasa[$i]
            [void]$cadeia.Add([pscustomobject]@{
                nivel            = $nivel
                caminho_original = $item.caminho_original
                nome_proposto    = $item.nome_proposto
            })
            $nivel++
        }

        $nomeProposto = $cadeiaProfundaParaRasa[0].nome_proposto
        $jaValido = ($cadeia.Count -eq 1) -and ($dirName -eq $nomeProposto) -and $resolvido

        [void]$diretorios.Add([pscustomobject]@{
            id               = $id
            diretorio        = $dir
            nome_original     = $dirName
            nome_proposto     = $nomeProposto
            caminho_original  = $dir
            caminho_proposto  = $novoCaminhoDirFinal
            total_arquivos    = $itens.Count
            maior_sufixo      = $maiorSufixo
            problemas         = $problemas
            problema_pred     = $problemaPredominante
            selecionado       = (-not $jaValido)
            ja_valido         = $jaValido
            resolvido         = $resolvido
            atingiu_raiz      = $atingiuRaiz
            editado_manualmente = $false
            cadeia            = $cadeia.ToArray()
        })
        $id++
    }

    return $diretorios
}
