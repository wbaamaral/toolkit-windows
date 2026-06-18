function Get-StartupItem {
    <#
    .SYNOPSIS
        Retorna todos os itens de inicializacao do Windows.

    .DESCRIPTION
        Agrega entradas de inicializacao de tres fontes: chaves Run do Registro,
        pasta Startup do usuario e do sistema, e tarefas agendadas com gatilho de
        logon ou boot. Itens desabilitados gerenciados (armazenados no registro WBA)
        substituem suas entradas originais para refletir o estado real.

    .EXAMPLE
        Get-StartupItem

        Retorna todos os itens de inicializacao encontrados no sistema.

    .EXAMPLE
        Get-StartupItem | Where-Object { $_.Enabled -eq $false }

        Lista apenas os itens desabilitados.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array de objetos com as propriedades: Id, Name, SourceType, Scope,
        Location, ValueName, Command, Enabled, State, ManagedDisabled,
        BackupPath, CanDisable, CanEnable, CanRemove.

    .NOTES
        Requer PowerShell 5.1 ou superior.
        Algumas fontes (ScheduledTask, pastas do sistema) podem exigir elevacao.
    #>
    [CmdletBinding()]
    param()

    $items = @(
        Get-RegistryStartupItems
        Get-StartupFolderItems
        Get-LogonStartupTaskItems
        Get-ManagedDisabledStartupItems
    )

    return @($items |
        Group-Object Id |
        ForEach-Object {
            $managed = @($_.Group | Where-Object { $_.ManagedDisabled } | Select-Object -First 1)
            if ($managed) { $managed } else { $_.Group | Select-Object -First 1 }
        } |
        Sort-Object SourceType, Scope, Name)
}
