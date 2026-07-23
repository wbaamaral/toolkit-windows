function Export-ConnectivityReportPdf {
    <#
    .SYNOPSIS
        Exporta o relatório HTML para PDF quando houver navegador compatível.

    .DESCRIPTION
        Detecta msedge, chrome ou chromium — primeiro no PATH e, se ausente (caso comum no Windows),
        em caminhos de instalação conhecidos (Program Files / LocalAppData) — e usa o modo headless para
        imprimir o HTML em PDF. Retorna Success=$false com mensagem se nenhum navegador for encontrado
        ou se o PDF não for efetivamente gerado.

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

    # 1) Tenta pelo PATH. No Windows, Edge/Chrome normalmente NAO estao no PATH, entao
    # 2) cai para caminhos de instalacao conhecidos (Program Files / LocalAppData).
    $browserPath = $null
    $fromPath = @('msedge', 'msedge.exe', 'chrome', 'chrome.exe', 'chromium', 'chromium-browser', 'google-chrome', 'google-chrome-stable') |
        ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue | Select-Object -First 1 } |
        Select-Object -First 1
    if ($fromPath) {
        $browserPath = if ($fromPath.Path) { $fromPath.Path } else { $fromPath.Source }
    }
    else {
        $candidatos = @()
        if ($env:ProgramFiles)        { $candidatos += (Join-Path $env:ProgramFiles        'Microsoft\Edge\Application\msedge.exe') }
        if (${env:ProgramFiles(x86)}) { $candidatos += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe') }
        if ($env:ProgramFiles)        { $candidatos += (Join-Path $env:ProgramFiles        'Google\Chrome\Application\chrome.exe') }
        if (${env:ProgramFiles(x86)}) { $candidatos += (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe') }
        if ($env:LOCALAPPDATA)        { $candidatos += (Join-Path $env:LOCALAPPDATA        'Google\Chrome\Application\chrome.exe') }
        $browserPath = $candidatos | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }

    if (-not $browserPath) {
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
