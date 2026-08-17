# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxCloudFileState {
    <#
    .SYNOPSIS
        Classifica o estado local (nuvem/local) de um item do Dropbox via atributos NTFS/Cloud Files.

    .DESCRIPTION
        Adaptacao de Get-CloudState/Test-FileAttribute/Test-AttributeByName do script
        autonomo original (dropbox-arquivos-v1.ps1). Le os atributos NTFS e os
        atributos de Cloud Files (Offline, ReparsePoint, RecallOnDataAccess,
        RecallOnOpen, Pinned, Unpinned) de um item e classifica como SomenteNuvem
        (placeholder) ou LocalENuvem (materializado). Nao classifica SomenteLocal
        com seguranca apenas via NTFS -- essa limitacao e deliberada e documentada
        no Motivo retornado.

    .PARAMETER Item
        Item de arquivo ou diretorio (System.IO.FileSystemInfo) a classificar.

    .EXAMPLE
        Get-DropboxCloudFileState -Item (Get-Item 'C:\Dropbox\arquivo.txt')

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com Estado, Motivo, Offline, ReparsePoint, RecallOnDataAccess,
        RecallOnOpen, Pinned, Unpinned, Attributes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    $attributesText = $Item.Attributes.ToString()

    $isOffline = (($Item.Attributes -band [System.IO.FileAttributes]::Offline) -eq [System.IO.FileAttributes]::Offline)
    $isReparsePoint = (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint)

    $isRecallOnDataAccess = $attributesText -match "(^|,\s*)RecallOnDataAccess(,|$)"
    $isRecallOnOpen       = $attributesText -match "(^|,\s*)RecallOnOpen(,|$)"
    $isPinned             = $attributesText -match "(^|,\s*)Pinned(,|$)"
    $isUnpinned           = $attributesText -match "(^|,\s*)Unpinned(,|$)"

    $cloudOnly = ($isOffline -or $isRecallOnDataAccess -or $isRecallOnOpen)

    if ($cloudOnly) {
        $state = 'SomenteNuvem'
        $reason = 'Placeholder detectado por atributos Offline/Recall.'
    }
    elseif ($isPinned) {
        $state = 'LocalENuvem'
        $reason = 'Conteudo materializado localmente e marcado como Pinned.'
    }
    else {
        $state = 'LocalENuvem'
        $reason = 'Conteudo aparentemente materializado localmente.'
    }

    return [pscustomobject]@{
        Estado             = $state
        Motivo             = $reason
        Offline            = $isOffline
        ReparsePoint       = $isReparsePoint
        RecallOnDataAccess = $isRecallOnDataAccess
        RecallOnOpen       = $isRecallOnOpen
        Pinned             = $isPinned
        Unpinned           = $isUnpinned
        Attributes         = $attributesText
    }
}
