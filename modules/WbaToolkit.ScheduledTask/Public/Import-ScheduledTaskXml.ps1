function Import-ScheduledTaskXml {
    <#
    .SYNOPSIS
        Importa uma tarefa agendada a partir de um arquivo XML.
    .PARAMETER XmlPath
        Caminho do arquivo XML.
    .PARAMETER TaskName
        Nome para a tarefa importada. Se omitido, usa o nome do RegistrationInfo/URI do XML
        ou, sem URI, o nome do arquivo.
    .PARAMETER TaskPath
        Caminho da pasta de destino. Se omitido, usa a pasta do URI do XML ou a raiz (\).
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

    if (-not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) { throw "Arquivo XML nao encontrado: $XmlPath" }

    # ReadAllText detecta o BOM: o Export-ScheduledTask e o schtasks gravam UTF-16; sem BOM, assume UTF-8.
    $xmlContent = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $XmlPath).ProviderPath)

    # O XML de tarefa nao tem <TaskName>: o nome e o caminho ficam em RegistrationInfo/URI (\Pasta\Nome).
    if (-not $TaskName) {
        if ($xmlContent -match '<URI>([^<]+)</URI>') {
            $uri = $Matches[1].Trim()
            $TaskName = ($uri -split '\\')[-1]
            if (-not $PSBoundParameters.ContainsKey('TaskPath')) {
                $parent = $uri.Substring(0, $uri.Length - $TaskName.Length)
                $TaskPath = if ($parent) { $parent } else { '\' }
            }
        } else {
            $TaskName = [System.IO.Path]::GetFileNameWithoutExtension($XmlPath)
        }
    }

    try {
        $task = Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Xml $xmlContent -ErrorAction Stop
        Write-Verbose "Tarefa '$TaskName' importada com sucesso."
        $task
    } catch {
        Write-Error "Falha ao importar tarefa: $_"
    }
}
