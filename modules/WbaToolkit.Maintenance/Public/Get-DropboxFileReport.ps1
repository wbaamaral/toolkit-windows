# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxFileReport {
    <#
    .SYNOPSIS
        Audita os arquivos de uma pasta Dropbox e classifica o estado local de cada item.

    .DESCRIPTION
        Nucleo do script autonomo original (dropbox-arquivos-v1.ps1), agora como
        funcao de modulo. Enumera o conteudo de -Path, classifica cada item via
        Get-DropboxCloudFileState e anexa os problemas de nome/caminho detectados
        por Get-DropboxProblemFileFlags. Retorna a lista completa e NAO filtrada --
        o filtro por relatorio (All/CloudOnly/LocalAndCloud/LocalOnly/Indeterminate)
        e responsabilidade de quem chama. Funcao silenciosa: sem Write-Host.

    .PARAMETER Path
        Diretorio raiz do Dropbox a analisar.

    .PARAMETER Recurse
        Analisa subdiretorios recursivamente. Padrao $true.

    .PARAMETER IncludeDirectories
        Inclui diretorios no relatorio, alem dos arquivos.

    .EXAMPLE
        Get-DropboxFileReport -Path 'C:\Users\usuario\Dropbox'

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Um objeto por item, com Estado, Tipo, Nome, Caminho, TamanhoBytes,
        TamanhoMB, Offline, Pinned, Unpinned, ReparsePoint, RecallOnDataAccess,
        RecallOnOpen, Attributes, Motivo, UltimaModificacao e ProblemFlags.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [bool]$Recurse = $true,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDirectories
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Diretorio nao encontrado: $Path"
    }

    $getChildItemParams = @{
        LiteralPath = $Path
        Force       = $true
    }
    if ($Recurse) {
        $getChildItemParams.Recurse = $true
    }

    try {
        $items = @(Get-ChildItem @getChildItemParams)
    }
    catch {
        throw "Falha ao enumerar '$Path': $($_.Exception.Message)"
    }

    if (-not $IncludeDirectories) {
        $items = @($items | Where-Object { -not $_.PSIsContainer })
    }

    $results = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($item in $items) {
        try {
            $cloudState = Get-DropboxCloudFileState -Item $item
            $problemFlags = @(Get-DropboxProblemFileFlags -Name $item.Name -FullPath $item.FullName)

            $length = if ($item.PSIsContainer) { $null } else { $item.Length }

            $results.Add([pscustomobject]@{
                Estado             = $cloudState.Estado
                Tipo               = if ($item.PSIsContainer) { 'Diretorio' } else { 'Arquivo' }
                Nome               = $item.Name
                Caminho            = $item.FullName
                TamanhoBytes       = $length
                TamanhoMB          = if ($null -ne $length) { [math]::Round($length / 1MB, 2) } else { $null }
                Offline            = $cloudState.Offline
                Pinned             = $cloudState.Pinned
                Unpinned           = $cloudState.Unpinned
                ReparsePoint       = $cloudState.ReparsePoint
                RecallOnDataAccess = $cloudState.RecallOnDataAccess
                RecallOnOpen       = $cloudState.RecallOnOpen
                Attributes         = $cloudState.Attributes
                Motivo             = $cloudState.Motivo
                UltimaModificacao  = $item.LastWriteTime
                ProblemFlags       = $problemFlags
            })
        }
        catch {
            Write-Verbose "Falha ao classificar '$($item.FullName)': $($_.Exception.Message)"
            $results.Add([pscustomobject]@{
                Estado             = 'Indeterminado'
                Tipo               = if ($item.PSIsContainer) { 'Diretorio' } else { 'Arquivo' }
                Nome               = $item.Name
                Caminho            = $item.FullName
                TamanhoBytes       = $null
                TamanhoMB          = $null
                Offline            = $null
                Pinned             = $null
                Unpinned           = $null
                ReparsePoint       = $null
                RecallOnDataAccess = $null
                RecallOnOpen       = $null
                Attributes         = $item.Attributes.ToString()
                Motivo             = "Erro: $($_.Exception.Message)"
                UltimaModificacao  = $item.LastWriteTime
                ProblemFlags       = @()
            })
        }
    }

    return @($results)
}
