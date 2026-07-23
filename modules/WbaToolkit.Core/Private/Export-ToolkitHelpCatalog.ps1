function Export-ToolkitHelpCatalog {
    <#
    .SYNOPSIS
        Gera o catalogo de ajuda do portal (ADR-0013): portal.pt-BR.json, categorias.pt-BR.json
        e garante a existencia de glossario.pt-BR.md.

    .DESCRIPTION
        Enumera funcoes exportadas (Get-Help + metadados WBA-DOCS) e scripts operacionais
        (Comment-Based Help extraida do bloco de ajuda do script) para montar um catalogo
        unico de ajuda curta/longa por categoria. Os arquivos JSON sao sempre regravados
        (dados derivados do codigo); glossario.pt-BR.md so e criado se ainda nao existir,
        pois e conteudo editorial.

    .PARAMETER ModulePath
        Caminho dos manifestos .psd1 dos modulos a catalogar.

    .PARAMETER ScriptPath
        Caminho dos scripts .ps1 a catalogar.

    .PARAMETER ManualPath
        Pasta onde os arquivos do catalogo sao gravados.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModulePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$ManualPath
    )

    # WBA-DOCS: Category=Documentacao; Related=Export-ToolkitDocumentation,Get-StaticDocsMetadata; Manual=Catalogo de ajuda do portal (ADR-0013)

    $catalog = [System.Collections.Generic.List[object]]::new()
    $categories = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Permite resolver RequiredModules a partir da árvore do repositório, mesmo
    # quando o catálogo é gerado fora de uma instalação de módulos do Windows.
    $modulesRoot = $ModulePath |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1 |
        ForEach-Object { Split-Path -Parent (Split-Path -Parent $_) }
    if ($modulesRoot -and (Test-Path -LiteralPath $modulesRoot)) {
        $psModulePathEntries = $env:PSModulePath -split [System.IO.Path]::PathSeparator
        if ($modulesRoot -notin $psModulePathEntries) {
            $env:PSModulePath = $modulesRoot + [System.IO.Path]::PathSeparator + $env:PSModulePath
        }
    }

    foreach ($path in $ModulePath) {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if (-not (Test-Path -LiteralPath $resolvedPath)) { continue }

        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
        $module = Get-Module -Name $moduleName | Select-Object -First 1
        if (-not $module) {
            $module = Import-Module $resolvedPath -Force -PassThru -DisableNameChecking -ErrorAction Stop
        }

        foreach ($command in ($module.ExportedFunctions.Values | Sort-Object Name)) {
            $help = Get-Help $command.Name -Full
            $docsMetadata = Get-StaticDocsMetadata -Command $command
            $category = if ($docsMetadata.ContainsKey('Category')) { [string]$docsMetadata.Category } else { 'Geral' }
            $categories[$category] = $category

            $catalog.Add([pscustomobject]@{
                Nome       = $command.Name
                Tipo       = 'Funcao'
                Modulo     = $module.Name
                Categoria  = $category
                AjudaCurta = [string]$help.Synopsis
                AjudaLonga = (@($help.description.Text) -join "`n")
            })
        }
    }

    foreach ($path in $ScriptPath) {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if (-not (Test-Path -LiteralPath $resolvedPath)) { continue }

        $scriptName = [System.IO.Path]::GetFileName($resolvedPath)
        $docsMetadata = Get-StaticDocsMetadata -Command (Get-Command -Name $resolvedPath)
        $category = if ($docsMetadata.ContainsKey('Category')) { [string]$docsMetadata.Category } else { 'Scripts' }
        $categories[$category] = $category

        $scriptContent = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
        $commentMatch = [regex]::Match($scriptContent, '(?s)<#(.*?)#>')
        $sections = [ordered]@{}

        if ($commentMatch.Success) {
            $currentSection = 'SYNOPSIS'
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

        $shortHelp = if ($sections.Contains('SYNOPSIS')) {
            (($sections['SYNOPSIS'] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
        } else { '' }
        $longHelp = if ($sections.Contains('DESCRIPTION')) {
            (($sections['DESCRIPTION'] | ForEach-Object { $_.TrimEnd() }) -join "`n").Trim()
        } else { '' }

        $catalog.Add([pscustomobject]@{
            Nome       = $scriptName
            Tipo       = 'Script'
            Modulo     = $null
            Categoria  = $category
            AjudaCurta = $shortHelp
            AjudaLonga = $longHelp
        })
    }

    $null = New-Item -Path $ManualPath -ItemType Directory -Force

    $catalogJson = @($catalog | Sort-Object Tipo, Nome) | ConvertTo-Json -Depth 4
    $catalogPath = Join-Path $ManualPath 'portal.pt-BR.json'
    Write-TextFileUtf8 -Path $catalogPath -Content $catalogJson

    $categoriesArray = @($categories.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ Slug = $_; Nome = $_ } })
    $categoriesPath = Join-Path $ManualPath 'categorias.pt-BR.json'
    Write-TextFileUtf8 -Path $categoriesPath -Content (@($categoriesArray) | ConvertTo-Json -Depth 2)

    $glossaryPath = Join-Path $ManualPath 'glossario.pt-BR.md'
    if (-not (Test-Path -LiteralPath $glossaryPath)) {
        $glossaryMd = @'
# Glossário do WBA Windows Toolkit

- **ADR** — Architecture Decision Record; registro formal de uma decisão de arquitetura ou processo do projeto.
- **CBH** — Comment-Based Help; bloco `<# ... #>` com `.SYNOPSIS`/`.DESCRIPTION` lido por `Get-Help`.
- **WBA-DOCS** — comentário `# WBA-DOCS: Category=...; Related=...; Manual=...` usado para gerar o catálogo e a referência técnica.
- **Sysprep** — generalização de uma instalação Windows para criação de imagem, removendo identidade de máquina.
- **WinSxS** — Component Store do Windows (`C:\Windows\WinSxS`), alvo da limpeza assistida do toolkit.
- **DISM** — Deployment Image Servicing and Management; ferramenta usada para limpeza e reparo de imagem.
- **Autologon** — logon automático configurado via segredo LSA, sem senha em texto claro no registro.
- **Portal do operador** — páginas HTML voltadas a quem executa o toolkit no dia a dia, sem contexto de desenvolvimento.
- **Referência técnica** — documentação HTML gerada a partir de CBH e metadados, voltada a quem mantém o código.
'@
        Write-TextFileUtf8 -Path $glossaryPath -Content $glossaryMd
    }

    [pscustomobject]@{
        CatalogPath    = $catalogPath
        CategoriesPath = $categoriesPath
        GlossaryPath   = $glossaryPath
        EntryCount     = $catalog.Count
        CategoryCount  = $categoriesArray.Count
    }
}
