# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxFrescorPastasCriticas {
    <#
    .SYNOPSIS
        Checagem de saude: frescor do conteudo de subpastas consideradas criticas.

    .DESCRIPTION
        Para cada subpasta relativa informada, emite AVISO se ela nao existir, se
        estiver vazia ou se o item mais recente for mais antigo que -FreshnessDays.
        Quando -CriticalFolders nao e informado, nao gera nenhuma checagem.

    .PARAMETER Path
        Caminho raiz do Dropbox sendo diagnosticado.

    .PARAMETER CriticalFolders
        Subpastas relativas consideradas criticas para a checagem de frescor.

    .PARAMETER FreshnessDays
        Numero maximo de dias sem atualizacao antes de gerar AVISO. Padrao 2.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$CriticalFolders = @(),

        [Parameter(Mandatory = $false)]
        [int]$FreshnessDays = 2
    )

    $results = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($folder in @($CriticalFolders | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $fullPath = Join-Path $Path $folder

        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            $results.Add((New-DropboxCheckResult -Categoria 'Frescor' -Nome "Pasta critica: $folder" -Status 'AVISO' `
                -Detalhe "A pasta critica '$folder' nao existe em $Path." `
                -Recomendacao 'Verifique se a estrutura de pastas esperada ainda existe.' -Penalidade 15))
            continue
        }

        $items = $null
        try {
            $items = @(Get-ChildItem -LiteralPath $fullPath -File -Recurse -ErrorAction Stop)
        }
        catch {
            $results.Add((New-DropboxCheckResult -Categoria 'Frescor' -Nome "Pasta critica: $folder" -Status 'AVISO' `
                -Detalhe "Falha ao inspecionar '$folder': $($_.Exception.Message)" -Penalidade 10))
            continue
        }

        if ($items.Count -eq 0) {
            $results.Add((New-DropboxCheckResult -Categoria 'Frescor' -Nome "Pasta critica: $folder" -Status 'AVISO' `
                -Detalhe "A pasta critica '$folder' esta vazia." -Penalidade 10))
            continue
        }

        $newest = $items | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $ageDays = [math]::Round((New-TimeSpan -Start $newest.LastWriteTime -End (Get-Date)).TotalDays, 1)

        if ($ageDays -gt $FreshnessDays) {
            $results.Add((New-DropboxCheckResult -Categoria 'Frescor' -Nome "Pasta critica: $folder" -Status 'AVISO' `
                -Detalhe "Item mais recente em '$folder' tem $ageDays dia(s), acima do limite de $FreshnessDays dia(s)." `
                -Recomendacao 'Confirme se a sincronizacao dessa pasta esta funcionando.' -Penalidade 15))
        }
        else {
            $results.Add((New-DropboxCheckResult -Categoria 'Frescor' -Nome "Pasta critica: $folder" -Status 'OK' `
                -Detalhe "Pasta critica '$folder' esta atualizada (item mais recente ha $ageDays dia(s))."))
        }
    }

    return @($results)
}
