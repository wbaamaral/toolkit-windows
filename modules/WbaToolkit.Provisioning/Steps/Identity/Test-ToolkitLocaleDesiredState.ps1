function Test-ToolkitLocaleDesiredState {
    <#
    .SYNOPSIS
        Etapa computer.locale — verifica se o fuso horario atende a configuracao.

    .DESCRIPTION
        Escopo da Fase 1 limitado a 'computer.timeZone', unico campo de fuso/regional
        presente no schema v1 (SPEC-PROVISIONING-CONFIG). Usada como TestFunction e
        VerifyFunction. Sem efeitos colaterais.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status, Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $config = $Context.Config
    $desiredTimeZone = $null
    if ($config -and $config.PSObject.Properties.Name -contains 'computer' -and
        $config.computer.PSObject.Properties.Name -contains 'timeZone') {
        $desiredTimeZone = [string]$config.computer.timeZone
    }

    if ([string]::IsNullOrWhiteSpace($desiredTimeZone)) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'computer.timeZone' nao declarada."; Evidence = $null }
    }

    $current = Get-TimeZone

    if ($current.Id -eq $desiredTimeZone) {
        return [pscustomobject]@{
            Status   = 'Compliant'
            Message  = "Fuso horario ja e '$desiredTimeZone'."
            Evidence = [pscustomobject]@{ CurrentTimeZoneId = $current.Id }
        }
    }

    return [pscustomobject]@{
        Status   = 'Changed'
        Message  = "Fuso horario diverge: atual '$($current.Id)', desejado '$desiredTimeZone'."
        Evidence = [pscustomobject]@{ CurrentTimeZoneId = $current.Id; DesiredTimeZoneId = $desiredTimeZone }
    }
}
