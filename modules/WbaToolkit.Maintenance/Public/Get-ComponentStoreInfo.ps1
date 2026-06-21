function Get-ComponentStoreInfo {
    <#
    .SYNOPSIS
        Analisa o Component Store (WinSxS) via DISM sem efetuar alteracoes.

    .DESCRIPTION
        Executa dism /Online /Cleanup-Image /AnalyzeComponentStore e parseia a saida,
        retornando um objeto estruturado com tamanho do store, espaco recuperavel,
        recomendacao de limpeza e data da ultima analise.

        Operacao somente leitura — segura para uso em modo diagnostico.

    .EXAMPLE
        $info = Get-ComponentStoreInfo
        Write-Host "Store: $($info.StoreSizeGB) GB — Recuperavel: $($info.ReclaimableSizeGB) GB"

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: StoreSizeGB, ReclaimableSizeGB, RecommendedCleanup, LastAnalysisDate,
        ExitCode, RawOutput. Retorna $null em caso de falha ao executar DISM.

    .NOTES
        Autor: wbaamaral
    #>
    [CmdletBinding()]
    param()

    $rawLines = @()
    $exitCode = 0

    try {
        # /English forca a saida em ingles independentemente do idioma do Windows
        # (alvo do projeto e pt-BR); mantem o parsing por rotulos em ingles estavel.
        $rawLines = & dism.exe /English /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Warning "Falha ao executar DISM AnalyzeComponentStore: $($_.Exception.Message)"
        return $null
    }

    $rawOutput       = ($rawLines | ForEach-Object { [string]$_ }) -join "`n"
    $storeSizeGB     = $null
    $reclaimableGB   = $null
    $recommended     = $null
    $lastAnalysis    = 'N/A'

    foreach ($rawLine in $rawLines) {
        $line = [string]$rawLine

        # Rotulo do tamanho do store varia por versao do DISM: builds atuais (19041+)
        # usam "Actual Size of Component Store"; versoes antigas, "Total (Installed) Size".
        # "Actual Size" aparece depois de "Windows Explorer Reported Size" e prevalece.
        if ($line -match '(?:Actual Size of Component Store|Windows Explorer Reported Size of Component Store|Total\s*\(Installed\)\s*Size)\s*:\s*([\d,\.]+)\s*(GB|MB|KB|bytes?)') {
            $storeSizeGB = ConvertTo-StoreSizeGB -Value $Matches[1] -Unit $Matches[2]
        }
        elseif ($line -match 'Backups?\s+and\s+Disabled\s+Features?\s*:\s*([\d,\.]+)\s*(GB|MB|KB|bytes?)') {
            $reclaimableGB = ConvertTo-StoreSizeGB -Value $Matches[1] -Unit $Matches[2]
        }
        elseif ($line -match 'Cleanup\s+Recommended\s*:\s*(Yes|No)') {
            $recommended = $Matches[1] -eq 'Yes'
        }
        elseif ($line -match 'Date\s+of\s+Last\s+Cleanup\s*:\s*(.+)') {
            $lastAnalysis = $Matches[1].Trim()
        }
    }

    # Se nenhum campo-chave foi reconhecido, a saida do DISM provavelmente nao esta
    # no formato esperado (idioma inesperado, versao diferente ou falha) — avisa em
    # vez de retornar campos nulos silenciosamente.
    if ($null -eq $storeSizeGB -and $null -eq $reclaimableGB -and $null -eq $recommended) {
        Write-Warning ("Saida do DISM AnalyzeComponentStore nao reconhecida (ExitCode $exitCode). " +
            'Campos de tamanho/recomendacao indisponiveis.')
    }

    [pscustomobject]@{
        StoreSizeGB        = $storeSizeGB
        ReclaimableSizeGB  = $reclaimableGB
        RecommendedCleanup = $recommended
        LastAnalysisDate   = $lastAnalysis
        ExitCode           = $exitCode
        RawOutput          = $rawOutput
    }
}
