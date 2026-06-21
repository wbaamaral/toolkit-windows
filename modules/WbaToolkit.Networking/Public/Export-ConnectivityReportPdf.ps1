function Export-ConnectivityReportPdf {
    <#
    .SYNOPSIS
        Exporta o relatório HTML para PDF quando houver navegador compatível.

    .DESCRIPTION
        Detecta msedge, chromium ou google-chrome e usa o modo headless para imprimir o HTML em PDF.
        Retorna um objeto com Success=$false e mensagem explicativa se nenhum navegador for encontrado.

    .PARAMETER HtmlPath
        Caminho completo do arquivo HTML de origem, gerado por Export-ConnectivityReport.

    .PARAMETER PdfPath
        Caminho de saída do PDF. Padrão: mesmo nome do HTML com extensão .pdf.

    .EXAMPLE
        Export-ConnectivityReportPdf -HtmlPath 'C:\WBA\Relatorios\Networking\relatorio.html'

    .EXAMPLE
        Export-ConnectivityReportPdf -HtmlPath 'C:\ti\relatorio.html' -PdfPath 'C:\ti\relatorio.pdf'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HtmlPath,

        [Parameter(Mandatory = $false)]
        [string]$PdfPath = ([System.IO.Path]::ChangeExtension($HtmlPath, '.pdf'))
    )

    $browser = @('msedge', 'msedge.exe', 'chromium', 'chromium-browser', 'google-chrome', 'google-chrome-stable') |
        ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue | Select-Object -First 1 } |
        Select-Object -First 1

    if (-not $browser) {
        return [pscustomobject]@{
            Success = $false
            Path    = $PdfPath
            Type    = 'PDF'
            Message = 'Nenhum navegador compatível foi encontrado para a exportação PDF.'
        }
    }

    $args = @(
        '--headless'
        '--disable-gpu'
        "--print-to-pdf=$PdfPath"
        $HtmlPath
    )

    try {
        $browserPath = if ($browser.Path) { $browser.Path } else { $browser.Source }
        & $browserPath @args | Out-Null

        # O navegador headless pode sair com codigo 0 sem gerar o PDF (HTML invalido,
        # destino sem permissao de escrita): so reportamos sucesso se o arquivo existir.
        if ((Test-Path -LiteralPath $PdfPath) -and ((Get-Item -LiteralPath $PdfPath).Length -gt 0)) {
            [pscustomobject]@{
                Success = $true
                Path    = $PdfPath
                Type    = 'PDF'
            }
        }
        else {
            [pscustomobject]@{
                Success = $false
                Path    = $PdfPath
                Type    = 'PDF'
                Message = "O navegador executou mas o PDF nao foi gerado em '$PdfPath'."
            }
        }
    }
    catch {
        [pscustomobject]@{
            Success = $false
            Path    = $PdfPath
            Type    = 'PDF'
            Message = $_.Exception.Message
        }
    }
}
