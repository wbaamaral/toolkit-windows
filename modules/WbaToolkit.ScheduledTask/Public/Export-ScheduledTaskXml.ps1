function Export-ScheduledTaskXml {
    <#
    .SYNOPSIS
        Exporta uma tarefa agendada como XML.
    .PARAMETER TaskName
        Nome da tarefa.
    .PARAMETER TaskPath
        Caminho da pasta (opcional).
    .PARAMETER OutputPath
        Caminho do arquivo XML de saida.
    .OUTPUTS
        Caminho do arquivo exportado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath,

        [string]$OutputPath
    )

    $task = Resolve-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    if (-not $task) { throw "Tarefa '$TaskName' nao encontrada." }

    $xml = Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath

    if (-not $OutputPath) {
        $safeName = ($task.TaskName -replace '[\\/:*?"<>|]', '_')
        $OutputPath = Join-Path $PWD "$safeName.xml"
    }

    # O XML do Agendador declara encoding="UTF-16"; em UTF-8 o arquivo contradiz a declaracao e leitores estritos recusam o
    # arquivo. Devolve so o caminho: a mensagem no pipeline ia junto para quem guarda o resultado.
    [System.IO.File]::WriteAllText($OutputPath, $xml, [System.Text.Encoding]::Unicode)
    Write-Verbose "Tarefa exportada para: $OutputPath"
    $OutputPath
}
