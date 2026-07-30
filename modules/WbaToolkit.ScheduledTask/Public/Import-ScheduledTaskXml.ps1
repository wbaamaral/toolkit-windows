function Import-ScheduledTaskXml {
    <#
    .SYNOPSIS
        Importa uma tarefa agendada a partir de um arquivo XML.
    .PARAMETER XmlPath
        Caminho do arquivo XML.
    .PARAMETER TaskName
        Nome para a tarefa importada. Se omitido, usa o nome do XML.
    .PARAMETER TaskPath
        Caminho da pasta de destino.
    .OUTPUTS
        Objeto da tarefa importada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$XmlPath,

        [string]$TaskName,

        [string]$TaskPath = '\'
    )

    if (-not (Test-Path $XmlPath)) { throw "Arquivo XML nao encontrado: $XmlPath" }

    $xmlContent = Get-Content -Path $XmlPath -Raw -Encoding UTF8

    if (-not $TaskName) {
        if ($xmlContent -match '<TaskName>(.+?)</TaskName>') {
            $TaskName = $Matches[1]
        } else {
            $TaskName = [System.IO.Path]::GetFileNameWithoutExtension($XmlPath)
        }
    }

    try {
        $task = Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Xml $xmlContent -ErrorAction Stop
        Write-Output "Tarefa '$TaskName' importada com sucesso."
        $task
    } catch {
        Write-Error "Falha ao importar tarefa: $_"
    }
}
