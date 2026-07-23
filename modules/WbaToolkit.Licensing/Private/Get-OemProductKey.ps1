function Get-OemProductKey {
    [CmdletBinding()]
    param()
    $key = $null
    try { $key = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name BackupProductKeyDefault -ErrorAction Stop).BackupProductKeyDefault } catch { Write-Verbose 'BackupProductKeyDefault não disponível.' }
    $partial = [string]$key
    if ($partial.Length -gt 5) { $partial = $partial.Substring($partial.Length - 5) }
    [pscustomobject]@{ PartialOemKey = $(if ($partial) { $partial } else { $null }); Found = [bool]$key }
}
