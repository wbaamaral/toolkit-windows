function Enable-ToolkitProvisioning {
    <#
    .SYNOPSIS
        Valida a configuracao disponivel e habilita a tarefa agendada de provisionamento.

    .DESCRIPTION
        Recusa habilitar sem uma configuracao valida ja localizavel (SPEC-PROVISIONING-ENGINE:
        instalar e habilitar sao operacoes distintas, e habilitar exige uma configuracao
        valida ja descoberta). Use -ConfigPath para apontar explicitamente a origem antes
        de gerar a imagem de referencia.

    .PARAMETER ConfigPath
        Caminho explicito da configuracao. Quando omitido, usa a precedencia padrao
        (Inbox, midia removivel).

    .EXAMPLE
        Enable-ToolkitProvisioning -ConfigPath C:\WBA\provisioning.json

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ConfigPath
    )

    $paths = Get-ToolkitProvisioningPaths
    $resolvedPath = Find-ToolkitProvisioningConfig -ConfigPath $ConfigPath -Paths $paths

    $imported = Import-ToolkitProvisioningConfig -Path $resolvedPath
    $validation = Test-ToolkitProvisioningSchema -Config $imported.Config

    if (-not $validation.IsValid) {
        throw "Configuracao invalida em '$resolvedPath'; habilitacao recusada. Erros: $($validation.Errors -join ' | ')"
    }

    if (-not $PSCmdlet.ShouldProcess('\WBA\Provisioning\Inicializar-Windows', 'Habilitar tarefa agendada de provisionamento')) {
        return [pscustomobject]@{ Success = $false; Message = 'Operacao cancelada (WhatIf).' }
    }

    $task = Get-ScheduledTask -TaskName 'Inicializar-Windows' -TaskPath '\WBA\Provisioning\' -ErrorAction Stop
    $task | Enable-ScheduledTask -ErrorAction Stop | Out-Null

    [pscustomobject]@{
        Success = $true
        Message = "Tarefa habilitada. Configuracao validada: '$resolvedPath' (SHA-256 $($imported.Sha256))."
    }
}
