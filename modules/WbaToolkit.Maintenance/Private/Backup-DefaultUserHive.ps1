function Backup-DefaultUserHive {
    <#
    .SYNOPSIS
        Cria uma copia de seguranca do arquivo NTUSER.DAT do perfil Default.

    .PARAMETER BackupsPath
        Diretorio de destino para o backup.

    .OUTPUTS
        System.String
        Caminho completo do arquivo de backup criado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupsPath
    )

    $hivePath  = Get-DefaultUserHivePath
    $timestamp = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
    $destino   = Join-Path $BackupsPath "NTUSER_Default_$timestamp.dat"

    if (-not (Test-Path -LiteralPath $BackupsPath)) {
        New-Item -Path $BackupsPath -ItemType Directory -Force | Out-Null
    }

    Copy-Item -LiteralPath $hivePath -Destination $destino -Force -ErrorAction Stop
    return $destino
}
