# Projeto: wba-toolkit
# Autor: wbaamaral

function Test-DropboxEspacoLivre {
    <#
    .SYNOPSIS
        Checagem de saude: espaco livre no volume que hospeda a pasta Dropbox.

    .DESCRIPTION
        AVISO se menos de 10% livre. FALHA critica se menos de 5% livre ou menos
        de 1GB livre.

    .PARAMETER Path
        Caminho raiz do Dropbox sendo diagnosticado.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # GetPathRoot nunca lanca (mesmo para UNC ou caminhos sem letra de unidade),
    # ao contrario de Split-Path -Qualifier. TrimEnd('\') normaliza 'C:\' para 'C:',
    # formato usado pelo DeviceID de Win32_LogicalDisk.
    $driveLetter = [System.IO.Path]::GetPathRoot($Path).TrimEnd('\')

    if ([string]::IsNullOrWhiteSpace($driveLetter)) {
        return New-DropboxCheckResult -Categoria 'Disco' -Nome 'Espaco livre' -Status 'AVISO' `
            -Detalhe "Nao foi possivel determinar a unidade do caminho informado: $Path" -Penalidade 5
    }

    $disk = Get-DropboxDiskFreeInfo -DriveLetter $driveLetter
    if ($null -eq $disk -or $null -eq $disk.Size -or [double]$disk.Size -eq 0) {
        return New-DropboxCheckResult -Categoria 'Disco' -Nome 'Espaco livre' -Status 'AVISO' `
            -Detalhe "Nao foi possivel consultar o espaco livre da unidade $driveLetter." -Penalidade 5
    }

    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $percentFree = [math]::Round(([double]$disk.FreeSpace / [double]$disk.Size) * 100, 1)
    $detail = "Unidade $driveLetter : $freeGB GB livres ($percentFree% do total)."

    if ($disk.FreeSpace -lt 1GB -or $percentFree -lt 5) {
        return New-DropboxCheckResult -Categoria 'Disco' -Nome 'Espaco livre' -Status 'FALHA' -Detalhe $detail `
            -Recomendacao 'Libere espaco na unidade; o Dropbox pausa a sincronizacao com pouco espaco livre.' `
            -Penalidade 30 -Critico
    }

    if ($percentFree -lt 10) {
        return New-DropboxCheckResult -Categoria 'Disco' -Nome 'Espaco livre' -Status 'AVISO' -Detalhe $detail `
            -Recomendacao 'Considere liberar espaco antes que a sincronizacao seja afetada.' -Penalidade 10
    }

    return New-DropboxCheckResult -Categoria 'Disco' -Nome 'Espaco livre' -Status 'OK' -Detalhe $detail
}
