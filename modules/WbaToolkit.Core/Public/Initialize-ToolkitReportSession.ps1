function Initialize-ToolkitReportSession {
    <#
    .SYNOPSIS
        Cria uma sessao padronizada de relatorio.

    .DESCRIPTION
        Resolve a raiz de relatorios, cria a pasta do script, cria a subpasta da execucao com timestamp
        e devolve caminhos padronizados para relatorios e logs.

        Estrutura: <ReportsRoot>/<scriptname>/<ddMMyyyy_HHmmss>/

    .PARAMETER ModuleName
        Nome do script/domínio funcional. Usado como subpasta na raiz de relatórios.

    .PARAMETER ReportsRoot
        Raiz de relatórios informada pelo chamador. Quando omitida, usa Get-ToolkitReportsRoot.

    .PARAMETER ExecutionName
        Nome da subpasta da execução. Padrão: timestamp no formato ddMMyyyy_HHmmss.

    .PARAMETER CreateBackups
        Se especificado, cria a subpasta 'backups' na sessão.

    .PARAMETER ConfigPath
        Caminho alternativo para o arquivo config.json. Quando omitido, usa o caminho padrão em ProgramData.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [string]$ReportsRoot,

        [Parameter(Mandatory = $false)]
        [string]$ExecutionName = (Get-Date -Format 'ddMMyyyy_HHmmss'),

        [switch]$CreateBackups,

        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    $root = Get-ToolkitReportsRoot -Path $ReportsRoot -ConfigPath $ConfigPath
    $modulePath = Join-Path $root $ModuleName
    $sessionPath = Join-Path $modulePath $ExecutionName
    $logsPath = Join-Path $sessionPath 'logs'
    $backupsPath = Join-Path $sessionPath 'backups'

    try {
        New-Item -Path $logsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        if ($CreateBackups) {
            New-Item -Path $backupsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        throw ("Nao foi possivel criar a sessao de relatorio em '{0}'. " +
            "Execute o PowerShell como Administrador, informe -DiretorioSaida/-OutputPath para um local gravavel " +
            "ou configure ReportsRoot com Set-ToolkitReportsRoot. Detalhes: {1}" -f $sessionPath, $_.Exception.Message)
    }

    return [pscustomobject]@{
        ReportsRoot = $root
        ModuleName = $ModuleName
        ModulePath = $modulePath
        ExecutionName = $ExecutionName
        Path = $sessionPath
        LogsPath = $logsPath
        BackupsPath = $backupsPath
    }
}
