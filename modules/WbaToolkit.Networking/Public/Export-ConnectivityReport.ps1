function Export-ConnectivityReport {
    <#
    .SYNOPSIS
        Exporta o relatório de conectividade para HTML.

    .DESCRIPTION
        Quando Path nao e informado, cria uma sessao padronizada em Networking\<timestamp> usando OutputPath,
        ReportsRoot persistente ou C:\WBA\Relatorios.

    .PARAMETER Report
        Objeto de relatorio gerado pelo teste de conectividade.

    .PARAMETER Path
        Caminho legado para arquivo HTML ou diretorio existente.

    .PARAMETER OutputPath
        Raiz de relatorios escolhida pelo usuario. O arquivo sera criado em Networking\<timestamp>.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Report,

        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $session = Initialize-ToolkitReportSession -ModuleName 'Networking'
        }
        else {
            $session = Initialize-ToolkitReportSession -ReportsRoot $OutputPath -ModuleName 'Networking'
        }

        $Path = $session.Path
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $fileName = 'relatorio-conectividade-{0}.html' -f $Report.ReportId
        $Path = Join-Path $Path $fileName
    }

    $html = ConvertTo-ConnectivityReportHtml -Report $Report
    $encoding = [System.Text.UTF8Encoding]::new($true)
    try {
        Write-TextFileUtf8 -Path $Path -Content $html
    }
    catch {
        throw "Nao foi possivel gravar o relatorio HTML em '$Path'. $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Success = $true
        Path    = $Path
        Type    = 'HTML'
    }
}
