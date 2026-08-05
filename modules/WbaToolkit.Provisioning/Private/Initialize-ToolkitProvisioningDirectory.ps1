function Initialize-ToolkitProvisioningDirectory {
    <#
    .SYNOPSIS
        Cria a arvore de diretorios de execucao do provisionamento com ACL restrita.

    .DESCRIPTION
        Cria Inbox/Work/Logs/Results/Secrets/Quarantine sob a raiz informada e aplica
        herenca removida com controle total apenas para SYSTEM e Administradores
        (SPEC-PROVISIONING-ENGINE). Idempotente: diretorios existentes nao sao recriados,
        mas a ACL e sempre reaplicada.

    .PARAMETER Paths
        Objeto retornado por Get-ToolkitProvisioningPaths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Paths
    )

    $directories = @($Paths.Root, $Paths.Inbox, $Paths.Work, $Paths.Logs, $Paths.Results, $Paths.Secrets, $Paths.Quarantine)

    foreach ($dir in $directories) {
        if (-not (Test-Path -LiteralPath $dir)) {
            if ($PSCmdlet.ShouldProcess($dir, 'Criar diretorio de provisionamento')) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
        }

        if ($PSCmdlet.ShouldProcess($dir, 'Restringir ACL a SYSTEM e Administradores')) {
            $acl = Get-Acl -LiteralPath $dir
            $acl.SetAccessRuleProtection($true, $false)
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

            # SID bem-conhecido em vez de nome: 'Administrators' nao resolve em Windows
            # localizado (ex.: PT-BR usa 'Administradores'); SID e universal.
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier(
                [System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
            $adminsSid = New-Object System.Security.Principal.SecurityIdentifier(
                [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $systemSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $adminsSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.SetAccessRule($systemRule)
            $acl.SetAccessRule($adminRule)
            Set-Acl -LiteralPath $dir -AclObject $acl -ErrorAction Stop
        }
    }
}
