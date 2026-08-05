function Find-ToolkitProvisioningConfig {
    <#
    .SYNOPSIS
        Resolve a origem unica e autorizada da configuracao de provisionamento.

    .DESCRIPTION
        Aplica a precedencia de SPEC-PROVISIONING-CONFIG: caminho explicito, Inbox do
        ProgramData e, por fim, midia removivel/CD-DVD contendo '\WBA\provisioning.json'
        marcada por '\WBA\provisioning.source'. Nao ha descoberta ampla por qualquer
        'cloud-config.json' e nao ha busca em HTTP. Mais de uma origem automatica valida
        e ambiguidade e falha.

    .PARAMETER ConfigPath
        Caminho explicito informado pelo operador ou pela tarefa agendada.

    .PARAMETER Paths
        Objeto de Get-ToolkitProvisioningPaths, usado para localizar o Inbox.

    .OUTPUTS
        System.String — caminho resolvido da configuracao.
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [pscustomobject]$Paths
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            throw "Configuracao indicada explicitamente nao encontrada: $ConfigPath"
        }
        return (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
    }

    $inboxConfig = Join-Path $Paths.Inbox 'provisioning.json'
    if (Test-Path -LiteralPath $inboxConfig -PathType Leaf) {
        return (Resolve-Path -LiteralPath $inboxConfig).ProviderPath
    }

    $removableCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($drive in @(Get-CimInstanceSafe -ClassName Win32_LogicalDisk |
                Where-Object { $_.DriveType -in 2, 5 })) {
        $marker = Join-Path $drive.DeviceID 'WBA\provisioning.source'
        $candidate = Join-Path $drive.DeviceID 'WBA\provisioning.json'
        if ((Test-Path -LiteralPath $marker -PathType Leaf) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $removableCandidates.Add((Resolve-Path -LiteralPath $candidate).ProviderPath)
        }
    }

    if ($removableCandidates.Count -eq 1) {
        return $removableCandidates[0]
    }

    if ($removableCandidates.Count -gt 1) {
        throw "Mais de uma origem automatica valida de configuracao foi encontrada em midia removivel: $($removableCandidates -join '; '). Execucao interrompida por ambiguidade."
    }

    throw 'Nenhuma configuracao de provisionamento encontrada (nem -ConfigPath, nem Inbox, nem midia removivel marcada).'
}
