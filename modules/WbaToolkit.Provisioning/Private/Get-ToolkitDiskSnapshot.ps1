function Get-ToolkitDiskSnapshot {
    <#
    .SYNOPSIS
        Coleta um retrato do estado de um disco para o inventario antes/depois exigido
        por SPEC-PROVISIONING-SECURITY.

    .PARAMETER DiskNumber

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uint32]$DiskNumber
    )

    $disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
    if (-not $disk) {
        return [pscustomobject]@{ DiskNumber = $DiskNumber; PartitionStyle = 'Desconhecido'; Volumes = @() }
    }

    $volumes = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | ForEach-Object {
            $vol = Get-Volume -Partition $_ -ErrorAction SilentlyContinue
            [pscustomobject]@{
                DriveLetter = $_.DriveLetter
                SizeBytes   = $_.Size
                FileSystem  = $(if ($vol) { $vol.FileSystem } else { $null })
                Label       = $(if ($vol) { $vol.FileSystemLabel } else { $null })
            }
        })

    [pscustomobject]@{
        DiskNumber     = $DiskNumber
        PartitionStyle = $disk.PartitionStyle
        Volumes        = $volumes
    }
}
