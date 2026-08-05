function Complete-ToolkitProvisioning {
    <#
    .SYNOPSIS
        Produz o relatorio final sanitizado e persiste em Results\<deploymentId>\.

    .DESCRIPTION
        Criterio de aceite do MVP: o relatorio final inclui plataforma, hash da
        configuracao, etapas, tentativas, reboots e resultado — tudo ja sanitizado, sem
        segredo, credencial ou PFX.

    .PARAMETER State
        Estado final do deployment.

    .PARAMETER Paths
        Objeto de Get-ToolkitProvisioningPaths.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — o relatorio persistido.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$State,

        [Parameter(Mandatory)]
        [pscustomobject]$Paths
    )

    $os = @(Get-CimInstanceSafe -ClassName Win32_OperatingSystem) | Select-Object -First 1

    $report = [pscustomobject]@{
        DeploymentId  = $State.DeploymentId
        GlobalState   = $State.GlobalState
        ConfigHash    = $State.ConfigHash
        SchemaVersion = $State.SchemaVersion
        ModuleVersion = $State.ModuleVersion
        BootCount     = $State.BootCount
        Platform      = [pscustomobject]@{
            Caption      = if ($os) { $os.Caption } else { 'desconhecida' }
            Version      = if ($os) { $os.Version } else { 'desconhecida' }
            BuildNumber  = if ($os) { $os.BuildNumber } else { 'desconhecida' }
        }
        Steps         = Protect-ToolkitProvisioningLogValue -InputObject $State.StepResults
        GeneratedAt   = (Get-Date).ToUniversalTime().ToString('o')
    }

    $resultDir = Join-Path $Paths.Results $State.DeploymentId
    if ($PSCmdlet.ShouldProcess($resultDir, 'Gravar relatorio final de provisionamento')) {
        if (-not (Test-Path -LiteralPath $resultDir)) {
            New-Item -Path $resultDir -ItemType Directory -Force | Out-Null
        }
        $reportPath = Join-Path $resultDir 'result.json'
        $json = $report | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($reportPath, $json, [System.Text.UTF8Encoding]::new($false))
    }

    if ($PSCmdlet.ShouldProcess('\WBA\Provisioning\Inicializar-Windows', 'Desabilitar tarefa agendada ao concluir')) {
        try {
            $task = Get-ScheduledTask -TaskName 'Inicializar-Windows' -TaskPath '\WBA\Provisioning\' -ErrorAction Stop
            $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Verbose "Nao foi possivel desabilitar a tarefa agendada ao concluir: $($_.Exception.Message)"
        }
    }

    return $report
}
