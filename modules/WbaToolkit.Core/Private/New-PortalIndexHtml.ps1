function New-PortalIndexHtml {
    [CmdletBinding()]
    param(
        [string]$ManualReadmePath,
        [string]$TechnicalReferenceUrl = 'referencia/index.html'
    )

    if ($ManualReadmePath -and (Test-Path -LiteralPath $ManualReadmePath)) {
        $raw = [System.IO.File]::ReadAllText($ManualReadmePath, [System.Text.Encoding]::UTF8)
        $readmeHtml = ConvertFrom-MarkdownSimple -Markdown $raw
    }
    else {
        if ($ManualReadmePath) {
            Write-Warning "New-PortalIndexHtml: catálogo não encontrado em '$ManualReadmePath'."
        }
        $readmeHtml = '<p class="text-gray-500">Catálogo não disponível.</p>'
    }

    $geradoEm = (Get-Date).ToString('yyyy-MM-dd HH:mm')

    $docLinks = @"
<ul>
  <li><a href="$TechnicalReferenceUrl">Referência técnica</a> — funções e scripts com Comment-Based Help</li>
</ul>
"@

    $body = @"
<p class="text-gray-500">Gerado em $geradoEm</p>

<h2>Documentação</h2>
$docLinks

<h2>Catálogo de scripts e módulos</h2>
$readmeHtml
"@

    ConvertTo-StaticDocsHtml -Title 'WBA Windows Toolkit — Portal' -Body $body
}
