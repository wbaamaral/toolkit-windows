function Export-ToolkitFunctionDocs {
    <#
    .SYNOPSIS
        Gera documentacao HTML estatica das funcoes exportadas e scripts do toolkit.

    .DESCRIPTION
        Importa os modulos informados, le o Comment-Based Help com Get-Help e gera paginas HTML locais com indice
        principal, paginas por modulo, paginas por funcao e paginas de documentacao dos scripts operacionais.

    .PARAMETER ModulePath
        Caminho dos manifestos ou modulos PowerShell usados como fonte da documentacao.

    .PARAMETER OutputPath
        Diretorio de saida dos arquivos HTML. O padrao e docs-html na raiz atual.

    .PARAMETER ScriptPath
        Caminho dos scripts operacionais que devem ter a documentacao incluida no HTML.

    .PARAMETER Force
        Permite recriar arquivos em um diretorio existente.

    .EXAMPLE
        Export-ToolkitFunctionDocs

    .EXAMPLE
        Export-ToolkitFunctionDocs -OutputPath C:\ti\manual-wba -Force
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ModulePath = @(
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules/WbaToolkit.Inventory/WbaToolkit.Inventory.psd1')
        ),

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'docs-html'),

        [Parameter(Mandatory = $false)]
        [string[]]$ScriptPath = @(
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/configuration/Configurar-Idioma-Regional.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts/diagnosticar-ad-cliente.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/diagnostics/networking/Testar-Conectividade-Internet.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/diagnostics/Diagnostico-Driver-Grafico.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts/Inventario-Hardware-Software.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/maintenance/Diagnostico-Reparo-HD100.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts/limpeza-windows.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts/atualizar-windows.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/utilities/Analise-Espaco-Disco.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/utilities/Remover-Perfis-Inativos.ps1')
        ),

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # WBA-DOCS: Category=Documentacao; Related=Get-Help,ConvertTo-HtmlSafe; Manual=Gera manual HTML estatico local

    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "O diretorio de saida ja existe. Use -Force para atualizar: $OutputPath"
    }

    $moduleOutputPath = Join-Path $OutputPath 'modules'
    $functionOutputPath = Join-Path $OutputPath 'functions'
    $scriptOutputPath = Join-Path $OutputPath 'scripts'
    New-Item -Path $moduleOutputPath -ItemType Directory -Force | Out-Null
    New-Item -Path $functionOutputPath -ItemType Directory -Force | Out-Null
    New-Item -Path $scriptOutputPath -ItemType Directory -Force | Out-Null

    $encoding = [System.Text.UTF8Encoding]::new($true)
    $moduleDocs = [System.Collections.ArrayList]::new()
    $scriptDocs = [System.Collections.ArrayList]::new()

    foreach ($path in $ModulePath) {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)

        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            Write-Warning "Modulo nao encontrado: $path"
            continue
        }

        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
        $module = Get-Module -Name $moduleName | Select-Object -First 1
        if (-not $module) {
            $module = Import-Module $resolvedPath -Force -PassThru -ErrorAction Stop
        }
        $commands = @($module.ExportedFunctions.Values | Sort-Object Name)
        $functionLinks = [System.Collections.ArrayList]::new()

        foreach ($command in $commands) {
            $help = Get-Help $command.Name -Full
            $docsMetadata = Get-StaticDocsMetadata -Command $command
            $functionFile = '{0}.html' -f (New-StaticDocsSlug -Name $command.Name)
            $functionRelativePath = Join-Path 'functions' $functionFile
            $functionPath = Join-Path $functionOutputPath $functionFile

            $metadataRows = @($docsMetadata.Keys | Sort-Object | ForEach-Object {
                $key = $_
                $value = [string]$docsMetadata[$key]

                if ($key -eq 'Related') {
                    $links = @($value -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                        $relatedName = $_.Trim()
                        $relatedFile = '{0}.html' -f (New-StaticDocsSlug -Name $relatedName)
                        '<a href="{0}">{1}</a>' -f $relatedFile, ([string](ConvertTo-HtmlSafe -Value $relatedName))
                    }) -join ', '
                    $valueHtml = $links
                }
                else {
                    $valueHtml = [string](ConvertTo-HtmlSafe -Value $value)
                }

                @"
<tr>
  <td><code>$([string](ConvertTo-HtmlSafe -Value $key))</code></td>
  <td>$valueHtml</td>
</tr>
"@
            }) -join "`r`n"

            $metadataSection = if ($metadataRows) {
                @"
<h2>Metadados do manual</h2>
<table>
  <thead><tr><th>Campo</th><th>Valor</th></tr></thead>
  <tbody>
$metadataRows
  </tbody>
</table>
"@
            }
            else {
                ''
            }

            $syntax = @($help.syntax.syntaxItem | ForEach-Object { $_.ToString().Trim() }) -join "`r`n"
            $description = @($help.description.Text) -join "`r`n"
            $examples = @($help.examples.example | ForEach-Object {
                $title = if ($_.title) { [string]$_.title } else { 'Exemplo' }
                $code = if ($_.code) { [string]$_.code } else { '' }
                $remarks = @($_.remarks.Text) -join "`r`n"
                @"
<h3>$([string](ConvertTo-HtmlSafe -Value $title))</h3>
<pre>$([string](ConvertTo-HtmlSafe -Value $code))</pre>
<p>$([string](ConvertTo-HtmlSafe -Value $remarks))</p>
"@
            }) -join "`r`n"

            $parameterRows = @($help.parameters.parameter | ForEach-Object {
                $parameterName = [string]$_.name
                $parameterType = [string]$_.type.name
                $required = [string]$_.required
                $parameterDescription = @($_.description.Text) -join ' '
                @"
<tr>
  <td><code>$([string](ConvertTo-HtmlSafe -Value $parameterName))</code></td>
  <td>$([string](ConvertTo-HtmlSafe -Value $parameterType))</td>
  <td>$([string](ConvertTo-HtmlSafe -Value $required))</td>
  <td>$([string](ConvertTo-HtmlSafe -Value $parameterDescription))</td>
</tr>
"@
            }) -join "`r`n"

            $body = @"
<p class="muted">Modulo: <a href="../modules/$([string](New-StaticDocsSlug -Name $module.Name)).html">$([string](ConvertTo-HtmlSafe -Value $module.Name))</a></p>
$metadataSection
<h2>Sinopse</h2>
<p>$([string](ConvertTo-HtmlSafe -Value $help.Synopsis))</p>
<h2>Descricao</h2>
<p>$([string](ConvertTo-HtmlSafe -Value $description))</p>
<h2>Sintaxe</h2>
<pre>$([string](ConvertTo-HtmlSafe -Value $syntax))</pre>
<h2>Parametros</h2>
<table>
  <thead><tr><th>Nome</th><th>Tipo</th><th>Obrigatorio</th><th>Descricao</th></tr></thead>
  <tbody>
$parameterRows
  </tbody>
</table>
<h2>Exemplos</h2>
$examples
"@

            $html = ConvertTo-StaticDocsHtml -Title $command.Name -Body $body -RelativePrefix '../'
            [System.IO.File]::WriteAllText($functionPath, $html, $encoding)

            $null = $functionLinks.Add([pscustomobject]@{
                Name = $command.Name
                Synopsis = [string]$help.Synopsis
                Category = if ($docsMetadata.ContainsKey('Category')) { [string]$docsMetadata.Category } else { '' }
                RelativePath = $functionRelativePath
            })
        }

        $moduleSlug = New-StaticDocsSlug -Name $module.Name
        $moduleFile = "$moduleSlug.html"
        $modulePath = Join-Path $moduleOutputPath $moduleFile
        $moduleCards = @($functionLinks | ForEach-Object {
            @"
<div class="card">
  <div class="card-title"><a href="../$($_.RelativePath)">$([string](ConvertTo-HtmlSafe -Value $_.Name))</a></div>
  <div class="card-meta">$([string](ConvertTo-HtmlSafe -Value $_.Synopsis))</div>
</div>
"@
        }) -join "`r`n"

        $moduleBody = @"
<p class="muted">Funcoes exportadas: $($commands.Count)</p>
<div class="grid">
$moduleCards
</div>
"@

        $moduleHtml = ConvertTo-StaticDocsHtml -Title $module.Name -Body $moduleBody -RelativePrefix '../'
        [System.IO.File]::WriteAllText($modulePath, $moduleHtml, $encoding)

        $null = $moduleDocs.Add([pscustomobject]@{
            Name = $module.Name
            RelativePath = Join-Path 'modules' $moduleFile
            FunctionCount = $commands.Count
            Functions = @($functionLinks)
        })
    }

    foreach ($path in $ScriptPath) {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)

        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            Write-Warning "Script nao encontrado: $path"
            continue
        }

        $scriptName = [System.IO.Path]::GetFileName($resolvedPath)
        $scriptSlug = New-StaticDocsSlug -Name $scriptName
        $scriptFile = "$scriptSlug.html"
        $scriptRelativePath = "scripts/$scriptFile"
        $scriptPagePath = Join-Path $scriptOutputPath $scriptFile
        $scriptCategory = Split-Path -Leaf (Split-Path -Parent $resolvedPath)
        $scriptContent = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
        $commentMatch = [regex]::Match($scriptContent, '(?s)<#(.*?)#>')
        $sections = [ordered]@{}

        if ($commentMatch.Success) {
            $currentSection = 'Documentacao'
            $sections[$currentSection] = New-Object 'System.Collections.Generic.List[string]'

            foreach ($line in ($commentMatch.Groups[1].Value -split "\r?\n")) {
                if ($line -match '^\s*\.(?<name>[A-Za-z0-9_-]+)\s*$') {
                    $currentSection = $Matches.name
                    if (-not $sections.Contains($currentSection)) {
                        $sections[$currentSection] = New-Object 'System.Collections.Generic.List[string]'
                    }
                    continue
                }

                $sections[$currentSection].Add($line.TrimEnd())
            }
        }

        $scriptSynopsis = if ($sections.Contains('SYNOPSIS')) {
            (($sections['SYNOPSIS'] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
        }
        else {
            'Documentacao operacional do script.'
        }

        $scriptSections = @($sections.Keys | Where-Object { $_ -ne 'Documentacao' } | ForEach-Object {
            $sectionName = $_
            $sectionText = (($sections[$sectionName] | ForEach-Object { $_.TrimEnd() }) -join "`r`n").Trim()
            if (-not [string]::IsNullOrWhiteSpace($sectionText)) {
                $sectionTitle = (Get-Culture).TextInfo.ToTitleCase($sectionName.ToLowerInvariant())
                if ($sectionName -in @('USO', 'EXAMPLE', 'EXAMPLES')) {
                    @"
<h2>$([string](ConvertTo-HtmlSafe -Value $sectionTitle))</h2>
<pre>$([string](ConvertTo-HtmlSafe -Value $sectionText))</pre>
"@
                }
                else {
                    @"
<h2>$([string](ConvertTo-HtmlSafe -Value $sectionTitle))</h2>
<p>$([string](ConvertTo-HtmlSafe -Value $sectionText))</p>
"@
                }
            }
        }) -join "`r`n"

        $scriptBody = @"
<p class="muted">Script operacional: <code>$([string](ConvertTo-HtmlSafe -Value $scriptName))</code></p>
<p class="muted">Categoria: $([string](ConvertTo-HtmlSafe -Value $scriptCategory))</p>
<h2>Como executar</h2>
<pre>.\$([string](ConvertTo-HtmlSafe -Value $scriptName))</pre>
$scriptSections
"@

        $scriptHtml = ConvertTo-StaticDocsHtml -Title $scriptName -Body $scriptBody -RelativePrefix '../'
        [System.IO.File]::WriteAllText($scriptPagePath, $scriptHtml, $encoding)

        $null = $scriptDocs.Add([pscustomobject]@{
            Name = $scriptName
            Category = $scriptCategory
            Synopsis = $scriptSynopsis
            RelativePath = $scriptRelativePath
        })
    }

    $indexCards = @($moduleDocs | ForEach-Object {
        @"
<div class="card">
  <div class="card-title"><a href="$($_.RelativePath)">$([string](ConvertTo-HtmlSafe -Value $_.Name))</a></div>
  <div class="card-meta">$($_.FunctionCount) funcoes exportadas</div>
</div>
"@
    }) -join "`r`n"

    $allFunctionRows = @($moduleDocs | ForEach-Object {
        $moduleName = $_.Name
        foreach ($function in $_.Functions) {
            @"
<tr>
  <td><a href="$($function.RelativePath)">$([string](ConvertTo-HtmlSafe -Value $function.Name))</a></td>
  <td>$([string](ConvertTo-HtmlSafe -Value $moduleName))</td>
  <td>$([string](ConvertTo-HtmlSafe -Value $function.Category))</td>
  <td>$([string](ConvertTo-HtmlSafe -Value $function.Synopsis))</td>
</tr>
"@
        }
    }) -join "`r`n"

    $scriptRows = @($scriptDocs | Sort-Object Category, Name | ForEach-Object {
        @"
<tr>
  <td><a href="$($_.RelativePath)">$([string](ConvertTo-HtmlSafe -Value $_.Name))</a></td>
  <td>$([string](ConvertTo-HtmlSafe -Value $_.Category))</td>
  <td>$([string](ConvertTo-HtmlSafe -Value $_.Synopsis))</td>
</tr>
"@
    }) -join "`r`n"

    $indexBody = @"
<p class="muted">Gerado em $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss'). Abra este arquivo localmente no navegador.</p>
<h2>Modulos</h2>
<div class="grid">
$indexCards
</div>
<h2>Indice de funcoes</h2>
<table>
  <thead><tr><th>Funcao</th><th>Modulo</th><th>Categoria</th><th>Resumo</th></tr></thead>
  <tbody>
$allFunctionRows
  </tbody>
</table>
<h2>Indice de scripts</h2>
<table>
  <thead><tr><th>Script</th><th>Categoria</th><th>Resumo</th></tr></thead>
  <tbody>
$scriptRows
  </tbody>
</table>
"@

    $indexHtml = ConvertTo-StaticDocsHtml -Title 'Manual de Funcoes do WBA Windows Toolkit' -Body $indexBody
    $indexPath = Join-Path $OutputPath 'index.html'
    [System.IO.File]::WriteAllText($indexPath, $indexHtml, $encoding)

    [pscustomobject]@{
        Success = $true
        Path = $indexPath
        OutputPath = $OutputPath
        ModuleCount = @($moduleDocs).Count
        FunctionCount = (@($moduleDocs | ForEach-Object { $_.FunctionCount }) | Measure-Object -Sum).Sum
        ScriptCount = @($scriptDocs).Count
    }
}
