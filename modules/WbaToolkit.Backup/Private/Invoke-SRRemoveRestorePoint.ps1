function Invoke-SRRemoveRestorePoint {
    <#
    .SYNOPSIS
        Remove um ponto de restauracao pelo numero de sequencia (SRRemoveRestorePoint).

    .DESCRIPTION
        Encapsula a API Win32 documentada SRRemoveRestorePoint (srclient.dll), a unica
        forma oficial de remover um ponto especifico pelo SequenceNumber exposto por
        Get-ComputerRestorePoint. A saida do 'vssadmin list shadows' nao contem o
        numero de sequencia, por isso nao serve para essa correspondencia.

    .OUTPUTS
        System.Int32 — codigo Win32 (0 = sucesso).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SequenceNumber
    )

    if (-not ('WbaToolkit.Backup.SystemRestoreApi' -as [type])) {
        Add-Type -Namespace 'WbaToolkit.Backup' -Name 'SystemRestoreApi' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("srclient.dll")]
public static extern int SRRemoveRestorePoint(int dwRPNum);
'@
    }

    return [WbaToolkit.Backup.SystemRestoreApi]::SRRemoveRestorePoint($SequenceNumber)
}
