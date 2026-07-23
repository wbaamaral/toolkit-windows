function Initialize-ScriptSession {
    <#
    .SYNOPSIS
        Cria uma sessao padronizada de script com caminhos de saida resolvidos.

    .DESCRIPTION
        Encapsula Initialize-ToolkitReportSession e retorna um objeto de sessao
        com os campos basicos prontos para uso: StartedAt, Mode, ReportsRoot,
        BasePath, Path, LogsPath e BackupsPath.

        Scripts que precisam de caminhos adicionais (ex.: TextReportPath,
        HtmlReportPath) devem acrescentar propriedades via Add-Member apos
        receber o objeto:

            $s = Initialize-ScriptSession -ModuleName 'HD100' -BasePath $dir -ExecutionMode $Modo
            $s | Add-Member -MemberType NoteProperty -Name 'TextReportPath' `
                 -Value (Join-Path $s.Path 'relatorio.txt')

    .PARAMETER ModuleName
        Nome do modulo ou dominio funcional, usado como subpasta de agrupamento
        dentro da raiz de relatorios.

    .PARAMETER BasePath
        Raiz de relatorios escolhida pelo chamador. Quando omitido, usa a
        configuracao persistente do toolkit ou C:\WBA\Relatorios.

    .PARAMETER ExecutionMode
        Modo de execucao do script (ex.: Diagnostico, Assistido, Rollback).
        Armazenado em Session.Mode para referencia nos relatorios.

    .EXAMPLE
        $session = Initialize-ScriptSession -ModuleName 'HD100' -BasePath $DiretorioSaida -ExecutionMode $Modo
        $session | Add-Member -MemberType NoteProperty -Name 'TextReportPath' `
            -Value (Join-Path $session.Path 'relatorio-hd100.txt')

        Cria uma sessao para o script HD100 e adiciona o caminho do relatorio TXT.

    .EXAMPLE
        $session = Initialize-ScriptSession -ModuleName 'Diagnostics' -ExecutionMode 'Diagnostico'

        Cria uma sessao usando a raiz de relatorios padrao do toolkit.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com as propriedades: StartedAt, Mode, ReportsRoot, BasePath,
        Path, LogsPath, BackupsPath.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [string]$BasePath,

        [Parameter(Mandatory = $false)]
        [string]$ExecutionMode
    )

    $reportSession = Initialize-ToolkitReportSession -ReportsRoot $BasePath -ModuleName $ModuleName

    return [pscustomobject]@{
        StartedAt   = Get-Date
        Mode        = $ExecutionMode
        ReportsRoot = $reportSession.ReportsRoot
        BasePath    = $reportSession.ModulePath
        Path        = $reportSession.Path
        LogsPath    = $reportSession.LogsPath
        BackupsPath = $reportSession.BackupsPath
    }
}
