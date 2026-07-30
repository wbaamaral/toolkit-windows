Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File)) {
    . $file.FullName
}

$publicPath = Join-Path $PSScriptRoot 'Public'
foreach ($file in @(Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File)) {
    . $file.FullName
}

Export-ModuleMember -Function @(
    'Get-SshServerStatus',
    'Install-SshServer',
    'Enable-SshServer',
    'Disable-SshServer',
    'Get-SshdConfig',
    'Set-SshdConfig',
    'New-SshHostKey',
    'New-SshUserKey',
    'Add-SshAuthorizedKey',
    'Remove-SshAuthorizedKey',
    'Get-SshAuthorizedKey',
    'Test-SshConnectivity'
)
