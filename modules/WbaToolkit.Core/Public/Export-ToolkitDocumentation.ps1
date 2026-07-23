function Export-ToolkitDocumentation {
<#
.SYNOPSIS
    Gera portal de documentação HTML unificado do WBA Windows Toolkit.

.DESCRIPTION
    Gera o portal operacional a partir de docs/README.md e a referência técnica HTML
    gerada por Export-ToolkitFunctionDocs. Compatível com PS 5.1.
    O resultado é um conjunto de arquivos estáticos para uso offline via file://.

.PARAMETER OutputPath
    Pasta de saída do portal. Padrão: .\docs\portal

.PARAMETER ManualPath
    Caminho para a pasta docs com os arquivos-fonte Markdown.
    Padrão: .\docs

.PARAMETER ModulePath
    Array de caminhos para os arquivos .psd1 dos módulos a documentar.
    Padrão: todos os módulos encontrados em modules/.

.PARAMETER ScriptPath
    Array de caminhos para os scripts .ps1 a documentar.
    Padrão: todos os 13 scripts do toolkit.

.PARAMETER Mode
    All     — portal + referência técnica + catálogo de ajuda (padrão)
    Portal  — apenas portal operacional (index.html)
    TechnicalReference — apenas referência técnica CBH (chama Export-ToolkitFunctionDocs)
    Help    — apenas catálogo de ajuda (ADR-0013): portal.pt-BR.json, categorias.pt-BR.json
              e glossario.pt-BR.md em ManualPath

.PARAMETER IncludeChangelog
    Converte CHANGELOG.md em changelog.html no portal.

.PARAMETER Force
    Sobrescreve OutputPath se já existir.

.EXAMPLE
    Export-ToolkitDocumentation -Mode All -Force
    Gera portal completo em .\docs\portal\.

.EXAMPLE
    Export-ToolkitDocumentation -Mode Portal -OutputPath C:\temp\portal -Force
    Gera apenas o portal operacional.

.EXAMPLE
    Export-ToolkitDocumentation -Mode Help
    Regrava apenas portal.pt-BR.json e categorias.pt-BR.json em ManualPath (glossario.pt-BR.md
    só é criado se ainda não existir).
#>
    # WBA-DOCS: Category=Documentacao; Related=Export-ToolkitFunctionDocs
    [CmdletBinding()]
    param(
        [string]$OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'docs/portal'),
        [string]$ManualPath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'docs'),
        [string[]]$ModulePath = @(
            Get-ChildItem -Path (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules') -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName "$($_.Name).psd1" } |
                Where-Object { Test-Path -LiteralPath $_ } |
                Sort-Object
        ),
        [string[]]$ScriptPath = @(
            Get-ChildItem -Path (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts') -Filter '*.ps1' -ErrorAction SilentlyContinue |
                Sort-Object Name | Select-Object -ExpandProperty FullName
        ),
        [ValidateSet('All', 'Portal', 'TechnicalReference', 'Help')]
        [string]$Mode = 'All',
        [switch]$IncludeChangelog,
        [switch]$Force
    )

    if ($Mode -ne 'Help' -and (Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "OutputPath '$OutputPath' já existe. Use -Force para sobrescrever."
    }

    $warningCount   = 0
    $portalIndex    = $null
    $technicalIndex = $null
    $helpCatalog    = $null
    $enc            = [System.Text.UTF8Encoding]::new($true)

    if ($Mode -in ('Portal', 'All')) {
        $null = New-Item -Path $OutputPath -ItemType Directory -Force

        # --- index.html ---
        $indexHtml  = New-PortalIndexHtml -ManualReadmePath (Join-Path $ManualPath 'README.md')
        $indexPath  = Join-Path $OutputPath 'index.html'
        Write-TextFileUtf8 -Path $indexPath -Content $indexHtml
        $portalIndex = $indexPath

        # --- changelog.html (opcional) ---
        if ($IncludeChangelog) {
            $changelogPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'CHANGELOG.md'
            if (Test-Path -LiteralPath $changelogPath) {
                $clMd   = [System.IO.File]::ReadAllText($changelogPath, $enc)
                $clBody = ConvertFrom-MarkdownSimple -Markdown $clMd
                $clHtml = ConvertTo-StaticDocsHtml -Title 'Changelog' -Body $clBody
                Write-TextFileUtf8 -Path (Join-Path $OutputPath 'changelog.html') -Content $clHtml
            }
            else {
                Write-Warning "Export-ToolkitDocumentation: CHANGELOG.md não encontrado."
                $warningCount++
            }
        }
    }

    if ($Mode -in ('TechnicalReference', 'All')) {
        $refPath  = Join-Path $OutputPath 'referencia'
        $refResult = Export-ToolkitFunctionDocs -OutputPath $refPath `
                        -ModulePath $ModulePath -ScriptPath $ScriptPath -Force
        $technicalIndex = $refResult.Path
    }

    if ($Mode -in ('Help', 'All')) {
        $helpCatalog = Export-ToolkitHelpCatalog -ModulePath $ModulePath -ScriptPath $ScriptPath -ManualPath $ManualPath
    }

    [pscustomobject]@{
        Success                 = $true
        Mode                    = $Mode
        OutputPath              = $OutputPath
        PortalIndex             = $portalIndex
        TechnicalReferenceIndex = $technicalIndex
        HelpCatalog             = $helpCatalog
        WarningCount            = $warningCount
    }
}
