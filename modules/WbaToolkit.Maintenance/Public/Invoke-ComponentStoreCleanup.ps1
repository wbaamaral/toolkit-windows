function Invoke-ComponentStoreCleanup {
    <#
    .SYNOPSIS
        Executa limpeza do Component Store (WinSxS) via DISM.

    .DESCRIPTION
        Nivel Standard executa /StartComponentCleanup — seguro e reversivel.
        Nivel Aggressive adiciona /ResetBase — IRREVERSIVEL: remove backups de updates
        instalados e impossibilita rollback de Service Packs.

        Suporta -DryRun (simulacao sem execucao) e -WhatIf (SupportsShouldProcess).
        Captura espaco liberado comparando disco antes e depois da execucao.

    .PARAMETER Level
        Standard  : executa /StartComponentCleanup (padrao).
        Aggressive: executa /StartComponentCleanup /ResetBase (IRREVERSIVEL).

    .PARAMETER DryRun
        Simula a operacao sem executar DISM. Retorna objeto com Success=$true
        e ExitCode=-1 indicando simulacao.

    .EXAMPLE
        Invoke-ComponentStoreCleanup

    .EXAMPLE
        Invoke-ComponentStoreCleanup -Level Aggressive -WhatIf

    .EXAMPLE
        Invoke-ComponentStoreCleanup -DryRun

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Propriedades: Level, ExitCode, SpaceFreedMB, RawOutput, Success.

    .NOTES
        Autor: wbaamaral
        ATENCAO: -Level Aggressive remove backups de updates. Rollback de SPs sera impossivel.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [ValidateSet('Standard', 'Aggressive')]
        [string]$Level = 'Standard',

        [Parameter()]
        [switch]$DryRun
    )

    if ($Level -eq 'Aggressive') {
        Write-Warning ('ATENCAO: /ResetBase remove backups de updates instalados. ' +
            'Rollback de SPs sera impossivel. Esta operacao e IRREVERSIVEL.')
    }

    if ($DryRun) {
        Write-Verbose "DRY-RUN: Invoke-ComponentStoreCleanup -Level $Level (nenhuma acao executada)."
        return [pscustomobject]@{
            Level        = $Level
            ExitCode     = -1
            SpaceFreedMB = 0
            RawOutput    = 'DryRun — nenhuma acao executada.'
            Success      = $true
        }
    }

    $dismArgs = if ($Level -eq 'Aggressive') {
        '/Online /Cleanup-Image /StartComponentCleanup /ResetBase'
    } else {
        '/Online /Cleanup-Image /StartComponentCleanup'
    }

    if (-not $PSCmdlet.ShouldProcess($env:SystemDrive, "dism.exe $dismArgs")) {
        return [pscustomobject]@{
            Level        = $Level
            ExitCode     = -1
            SpaceFreedMB = 0
            RawOutput    = 'WhatIf — nenhuma acao executada.'
            Success      = $true
        }
    }

    $diskBefore = Get-DiskInfo
    $rawLines   = @()
    $exitCode   = 0

    try {
        if ($Level -eq 'Aggressive') {
            $rawLines = & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
        }
        else {
            $rawLines = & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
        }
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Warning "Falha ao executar DISM StartComponentCleanup: $($_.Exception.Message)"
        return [pscustomobject]@{
            Level        = $Level
            ExitCode     = -1
            SpaceFreedMB = 0
            RawOutput    = $_.Exception.Message
            Success      = $false
        }
    }

    $diskAfter    = Get-DiskInfo
    $spaceFreedMB = 0
    if ($null -ne $diskBefore -and $null -ne $diskAfter) {
        $delta = ($diskAfter.LivreGB - $diskBefore.LivreGB) * 1024
        if ($delta -gt 0) {
            $spaceFreedMB = [math]::Round($delta, 1)
        }
    }

    $rawOutput = ($rawLines | ForEach-Object { [string]$_ }) -join "`n"

    [pscustomobject]@{
        Level        = $Level
        ExitCode     = $exitCode
        SpaceFreedMB = $spaceFreedMB
        RawOutput    = $rawOutput
        Success      = ($exitCode -eq 0)
    }
}
