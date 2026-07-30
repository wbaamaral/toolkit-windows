@{
    RootModule        = 'WbaToolkit.SSH.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'wbaamaral'
    CompanyName       = 'wbaamaral'
    Copyright         = '(c) wbaamaral. All rights reserved.'
    Description       = 'Gerenciamento de OpenSSH Server, chaves e configuracao SSH no Windows.'
    PowerShellVersion = '5.1'
    RequiredModules   = @(
        @{ ModuleName = 'WbaToolkit.Core'; ModuleVersion = '1.0.0' }
    )
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('WBA', 'SSH', 'OpenSSH', 'sshd', 'keys') } }
}
