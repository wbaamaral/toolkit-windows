function Test-ToolkitStorageDesiredState {
    <#
    .SYNOPSIS
        Etapa storage.configure — verifica se os discos declarados estao inicializados,
        particionados e formatados conforme a configuracao.

    .DESCRIPTION
        Identificacao por serial, unique ID, ou combinacao de barramento/localizacao/
        tamanho (nunca por indice). Identificacao ambigua, ausente, ou que resolva para o
        disco de sistema/boot falha a etapa inteira sem tocar em nenhum disco — mesmo
        principio de seguranca de SPEC-PROVISIONING-SECURITY para a etapa de rede.

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
    if (-not (($config -and (Test-ToolkitPropertyPresent -InputObject $config -Name 'storage')) -and
            (Test-ToolkitPropertyPresent -InputObject $config.storage -Name 'disks'))) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'storage.disks' nao declarada."; Evidence = $null }
    }

    $entries = @($config.storage.disks)
    if ($entries.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "'storage.disks' esta vazio."; Evidence = $null }
    }

    $evaluations = @()
    foreach ($entry in $entries) {
        $resolved = Resolve-ToolkitDisk -Match $entry.match
        if (-not $resolved.Found) {
            return [pscustomobject]@{
                Status   = 'Failed'
                Message  = "Falha ao identificar disco '$($entry.name)': $($resolved.Message)"
                Evidence = [pscustomobject]@{ Entry = $entry.name; Reason = $resolved.Message }
            }
        }

        $disk = $resolved.Disk
        $desiredFileSystem = if (Test-ToolkitPropertyPresent -InputObject $entry -Name 'fileSystem') { [string]$entry.fileSystem } else { 'NTFS' }
        # Filtra por Type 'Basic': Initialize-Disk -PartitionStyle GPT pode criar
        # automaticamente uma particao 'Reserved' (MSR) sem letra de unidade, que nao
        # deve ser confundida com a particao de dados que esta etapa gerencia.
        $partition = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -eq 'Basic' } | Select-Object -First 1
        # Get-Volume por -DriveLetter (char simples), nunca por -Partition (exige CimInstance
        # genuino e impede testar com mocks).
        $volume = if ($partition -and $partition.DriveLetter) { Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue } else { $null }

        $isCompliant = ($disk.PartitionStyle -eq 'GPT') -and $partition -and $volume -and
            ($volume.FileSystem -eq $desiredFileSystem) -and
            (-not (Test-ToolkitPropertyPresent -InputObject $entry -Name 'driveLetter') -or $partition.DriveLetter -eq [string]$entry.driveLetter)

        $evaluations += [pscustomobject]@{
            Name        = $entry.name
            DiskNumber  = $disk.Number
            IsCompliant = [bool]$isCompliant
            Current     = [pscustomobject]@{
                PartitionStyle = $disk.PartitionStyle
                FileSystem     = $(if ($volume) { $volume.FileSystem } else { $null })
                DriveLetter    = $(if ($partition) { $partition.DriveLetter } else { $null })
            }
        }
    }

    $nonCompliant = @($evaluations | Where-Object { -not $_.IsCompliant })
    $evidence = [pscustomobject]@{ Disks = $evaluations }

    if ($nonCompliant.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'Todos os discos declarados ja atendem a configuracao.'; Evidence = $evidence }
    }

    $names = ($nonCompliant | ForEach-Object { $_.Name }) -join ', '
    return [pscustomobject]@{ Status = 'Changed'; Message = "Discos pendentes de configuracao: $names."; Evidence = $evidence }
}
