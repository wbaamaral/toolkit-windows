function Resolve-ToolkitLocalGroup {
    <#
    .SYNOPSIS
        Resolve um grupo local pelo SID bem-conhecido quando o nome declarado for um dos
        grupos built-in comuns; caso contrario, resolve pelo nome literal.

    .DESCRIPTION
        SPEC-PROVISIONING-SECURITY: 'grupos sao resolvidos por SID conhecido quando
        possivel, evitando dependencia do idioma'. 'Administrators' e o nome em ingles do
        grupo, mas em Windows localizado (ex.: PT-BR) o nome real e 'Administradores' —
        resolver pelo SID (S-1-5-32-544) e independente de idioma.

    .PARAMETER Name
        Nome declarado na configuracao (ex.: 'Administrators', 'Remote Desktop Users').

    .OUTPUTS
        Microsoft.PowerShell.Commands.LocalGroup, ou $null se nao encontrado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $wellKnownSids = @{
        'Administrators'         = 'S-1-5-32-544'
        'Users'                  = 'S-1-5-32-545'
        'Guests'                 = 'S-1-5-32-546'
        'Backup Operators'       = 'S-1-5-32-551'
        'Remote Desktop Users'   = 'S-1-5-32-555'
        'Remote Management Users' = 'S-1-5-32-580'
    }

    if ($wellKnownSids.ContainsKey($Name)) {
        $group = Get-LocalGroup -SID $wellKnownSids[$Name] -ErrorAction SilentlyContinue
        if ($group) {
            return $group
        }
    }

    return Get-LocalGroup -Name $Name -ErrorAction SilentlyContinue
}
