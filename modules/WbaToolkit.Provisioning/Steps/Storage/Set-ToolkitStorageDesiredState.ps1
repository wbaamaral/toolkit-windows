function Set-ToolkitStorageDesiredState {
    <#
    .SYNOPSIS
        Etapa storage.configure — inicializa, particiona e formata os discos pendentes.

    .DESCRIPTION
        Exige 'policy.allowDestructiveStorage: true' no documento — sem essa politica
        explicita, a etapa recusa qualquer alteracao (SPEC-PROVISIONING-SECURITY: modo de
        execucao real exige a politica explicita no documento assinado). Reconfirma que o
        disco resolvido nao e o de sistema/boot antes de qualquer operacao destrutiva
        (defesa em profundidade; Resolve-ToolkitDisk ja recusa, mas a etapa nunca confia
        apenas na chamada anterior). Registra inventario antes e depois de cada disco.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $allowDestructive = (Test-ToolkitPropertyPresent -InputObject $Context.Config -Name 'policy') -and
        (Test-ToolkitPropertyPresent -InputObject $Context.Config.policy -Name 'allowDestructiveStorage') -and
        [bool]$Context.Config.policy.allowDestructiveStorage

    if (-not $allowDestructive) {
        throw "storage.configure requer 'policy.allowDestructiveStorage: true' explicito no documento; execucao recusada."
    }

    $applied = @()
    $inventory = @()

    foreach ($entry in @($Context.Config.storage.disks)) {
        $resolved = Resolve-ToolkitDisk -Match $entry.match
        if (-not $resolved.Found) {
            throw "Falha ao identificar disco '$($entry.name)' durante Set: $($resolved.Message)"
        }

        $disk = $resolved.Disk
        if ($disk.IsSystem -or $disk.IsBoot) {
            throw "Disco '$($entry.name)' resolveu para o disco de sistema/boot; operacao recusada (defesa em profundidade)."
        }

        $before = Get-ToolkitDiskSnapshot -DiskNumber $disk.Number

        $desiredFileSystem = if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'fileSystem') { [string]$entry.fileSystem } else { 'NTFS' }
        $desiredLabel = if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'label') { [string]$entry.label } else { $entry.name }

        if (-not $PSCmdlet.ShouldProcess("Disco $($disk.Number) ($($entry.name))", 'Inicializar, particionar e formatar')) {
            continue
        }

        if ($disk.PartitionStyle -eq 'RAW') {
            Initialize-Disk -Number $disk.Number -PartitionStyle GPT -Confirm:$false
        }

        # Filtra por Type 'Basic': Initialize-Disk -PartitionStyle GPT pode criar
        # automaticamente uma particao 'Reserved' (MSR) sem letra de unidade, que nao
        # deve ser confundida com a particao de dados que esta etapa gerencia.
        $existingPartition = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -eq 'Basic' } | Select-Object -First 1
        if (-not $existingPartition) {
            $partitionParams = @{ DiskNumber = $disk.Number; UseMaximumSize = $true }
            if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'driveLetter') {
                $partitionParams['DriveLetter'] = [string]$entry.driveLetter
            }
            else {
                $partitionParams['AssignDriveLetter'] = $true
            }
            $existingPartition = New-Partition @partitionParams
        }

        # Get-Volume/Format-Volume por -DriveLetter (char simples), nunca por -Partition
        # (exige CimInstance genuino e impede testar com mocks).
        $driveLetter = $existingPartition.DriveLetter
        $existingVolume = if ($driveLetter) { Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue } else { $null }
        if (-not $existingVolume -or $existingVolume.FileSystem -ne $desiredFileSystem) {
            Format-Volume -DriveLetter $driveLetter -FileSystem $desiredFileSystem -NewFileSystemLabel $desiredLabel -Confirm:$false | Out-Null
        }

        $after = Get-ToolkitDiskSnapshot -DiskNumber $disk.Number
        $inventory += [pscustomobject]@{ Name = $entry.name; DiskNumber = $disk.Number; Before = $before; After = $after }
        $applied += $entry.name
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Discos configurados: $($applied -join ', ')."
        Evidence       = [pscustomobject]@{ Inventory = $inventory }
    }
}
