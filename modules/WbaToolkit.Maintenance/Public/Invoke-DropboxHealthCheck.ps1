# Projeto: wba-toolkit
# Autor: wbaamaral

function Invoke-DropboxHealthCheck {
    <#
    .SYNOPSIS
        Executa o diagnostico completo de saude do cliente Dropbox.

    .DESCRIPTION
        Orquestra as checagens privadas Test-Dropbox* (processo, instalacao,
        espaco em disco, arquivos problematicos, frescor de pastas criticas,
        conectividade, proxy, exclusao no Defender, hora do sistema) e calcula
        um score de saude (0-100, mesma formula de Get-AdHealthSummary em
        diagnosticar-ad-cliente.ps1: comeca em 100, subtrai a Penalidade de cada
        checagem, com piso 0 e teto 100). Funcao silenciosa: sem Write-Host.

    .PARAMETER Path
        Raiz do Dropbox a diagnosticar. Se omitido, usa Get-DropboxInstallation e
        exige exatamente 1 resultado -- caso contrario, lanca erro orientando a
        informar -Path.

    .PARAMETER CriticalFolders
        Subpastas relativas consideradas criticas para a checagem de frescor.

    .PARAMETER FreshnessDays
        Numero maximo de dias sem atualizacao nas pastas criticas antes de gerar
        AVISO. Padrao 2.

    .EXAMPLE
        Invoke-DropboxHealthCheck -Path 'C:\Users\usuario\Dropbox'

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com Path, Score, Label, CriticalCount, WarningCount, Checks e
        FileReport.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$CriticalFolders = @(),

        [Parameter(Mandatory = $false)]
        [int]$FreshnessDays = 2
    )

    $installations = @(Get-DropboxInstallation)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($installations.Count -ne 1) {
            throw "Nao foi possivel resolver automaticamente uma unica pasta Dropbox ($($installations.Count) encontrada(s)). Informe -Path explicitamente."
        }
        $Path = $installations[0].Caminho
    }

    $checks = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($check in @(Test-DropboxProcesso)) { $checks.Add($check) }
    foreach ($check in @(Test-DropboxInstalacao -Installations $installations -Path $Path)) { $checks.Add($check) }
    foreach ($check in @(Test-DropboxEspacoLivre -Path $Path)) { $checks.Add($check) }

    $fileReport = @(Get-DropboxFileReport -Path $Path)

    foreach ($check in @(Test-DropboxArquivosProblema -FileReport $fileReport)) { $checks.Add($check) }
    foreach ($check in @(Test-DropboxFrescorPastasCriticas -Path $Path -CriticalFolders $CriticalFolders -FreshnessDays $FreshnessDays)) { $checks.Add($check) }
    foreach ($check in @(Test-DropboxConectividade)) { $checks.Add($check) }
    foreach ($check in @(Test-DropboxProxy)) { $checks.Add($check) }
    foreach ($check in @(Test-DropboxExclusaoDefender -Paths @($Path))) { $checks.Add($check) }
    foreach ($check in @(Test-DropboxHoraSistema)) { $checks.Add($check) }

    $score = 100
    foreach ($check in $checks) {
        $score -= [math]::Max(0, [int]$check.Penalidade)
    }
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    $critical = @($checks | Where-Object { $_.Status -eq 'FALHA' -and $_.Critico })
    $warn = @($checks | Where-Object { $_.Status -eq 'AVISO' })

    $label = if ($critical.Count -gt 0) {
        'Critico'
    }
    elseif ($warn.Count -gt 0) {
        if ($score -ge 75) { 'Bom' } else { 'Degradado' }
    }
    else {
        'Excelente'
    }

    return [pscustomobject]@{
        Path          = $Path
        Score         = $score
        Label         = $label
        CriticalCount = $critical.Count
        WarningCount  = $warn.Count
        Checks        = $checks.ToArray()
        FileReport    = $fileReport
    }
}
