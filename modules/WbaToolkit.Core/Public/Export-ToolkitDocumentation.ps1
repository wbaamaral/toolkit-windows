function Export-ToolkitDocumentation {
<#
.SYNOPSIS
    Gera portal de documentação HTML unificado do WBA Windows Toolkit.

.DESCRIPTION
    Combina o portal operacional (index.html, operador.html) convertido de Markdown com
    a referência técnica HTML gerada por Export-ToolkitFunctionDocs. Compatível com PS 5.1.
    O resultado é um conjunto de arquivos estáticos para uso offline via file://.

.PARAMETER OutputPath
    Pasta de saída do portal. Padrão: .\docs\portal

.PARAMETER ManualPath
    Caminho para a pasta docs\manual com os arquivos-fonte Markdown.
    Padrão: .\docs\manual

.PARAMETER ModulePath
    Array de caminhos para os arquivos .psd1 dos módulos a documentar.
    Padrão: todos os 4 módulos do toolkit.

.PARAMETER ScriptPath
    Array de caminhos para os scripts .ps1 a documentar.
    Padrão: todos os 13 scripts do toolkit.

.PARAMETER Mode
    All     — portal + referência técnica (padrão)
    Portal  — apenas portal operacional (index.html e operador.html)
    TechnicalReference — apenas referência técnica CBH (chama Export-ToolkitFunctionDocs)

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
#>
    # WBA-DOCS: Category=Documentacao; Related=Export-ToolkitFunctionDocs
    [CmdletBinding()]
    param(
        [string]$OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'docs/portal'),
        [string]$ManualPath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'manuais'),
        [string[]]$ModulePath = @(
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules/WbaToolkit.Networking/WbaToolkit.Networking.psd1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules/WbaToolkit.Startup/WbaToolkit.Startup.psd1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1')
        ),
        [string[]]$ScriptPath = @(
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/configuration/Configurar-Idioma-Regional.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/diagnostics/Diagnostico-Driver-Grafico.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts/diagnosticar-ad-cliente.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/diagnostics/networking/Testar-Conectividade-Internet.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/inventory/Inventario-Hardware-Software.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/maintenance/Diagnostico-Reparo-HD100.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/maintenance/Gerenciar-Inicializacao-Windows.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts/limpeza-windows.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/maintenance/Preparar-Imagem-Windows.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts/atualizar-windows.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/utilities/Analise-Espaco-Disco.ps1'),
            (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'experimental/utilities/Remover-Perfis-Inativos.ps1')
        ),
        [ValidateSet('All', 'Portal', 'TechnicalReference')]
        [string]$Mode = 'All',
        [switch]$IncludeChangelog,
        [switch]$Force
    )

    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "OutputPath '$OutputPath' já existe. Use -Force para sobrescrever."
    }

    $warningCount   = 0
    $portalIndex    = $null
    $technicalIndex = $null
    $enc            = [System.Text.UTF8Encoding]::new($true)

    if ($Mode -in ('Portal', 'All')) {
        $null = New-Item -Path $OutputPath -ItemType Directory -Force

        # --- index.html ---
        $indexHtml  = New-PortalIndexHtml -ManualReadmePath (Join-Path $ManualPath 'README.md')
        $indexPath  = Join-Path $OutputPath 'index.html'
        [System.IO.File]::WriteAllText($indexPath, $indexHtml, $enc)
        $portalIndex = $indexPath

        # --- operador.html ---
        $guiaPath = Join-Path $ManualPath 'operador\guia-rapido.md'
        if (Test-Path -LiteralPath $guiaPath) {
            $guiaMd   = [System.IO.File]::ReadAllText($guiaPath, $enc)
            $guiaBody = ConvertFrom-MarkdownSimple -Markdown $guiaMd
            $guiaHtml = ConvertTo-StaticDocsHtml -Title 'Guia Rápido do Operador' -Body $guiaBody
            [System.IO.File]::WriteAllText((Join-Path $OutputPath 'operador.html'), $guiaHtml, $enc)
        }
        else {
            Write-Warning "Export-ToolkitDocumentation: guia-rapido.md não encontrado em '$guiaPath'."
            $warningCount++
        }

        # --- changelog.html (opcional) ---
        if ($IncludeChangelog) {
            $changelogPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'CHANGELOG.md'
            if (Test-Path -LiteralPath $changelogPath) {
                $clMd   = [System.IO.File]::ReadAllText($changelogPath, $enc)
                $clBody = ConvertFrom-MarkdownSimple -Markdown $clMd
                $clHtml = ConvertTo-StaticDocsHtml -Title 'Changelog' -Body $clBody
                [System.IO.File]::WriteAllText((Join-Path $OutputPath 'changelog.html'), $clHtml, $enc)
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

    [pscustomobject]@{
        Success                = $true
        Mode                   = $Mode
        OutputPath             = $OutputPath
        PortalIndex            = $portalIndex
        TechnicalReferenceIndex = $technicalIndex
        WarningCount           = $warningCount
    }
}
