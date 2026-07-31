﻿@{
    RootModule        = 'WbaToolkit.Licensing.psm1'
    ModuleVersion     = '0.4.0'
    GUID              = '89bdf78c-2e42-4b5e-a9e0-6c9f3a87b2d1'
    Author            = 'wbaamaral'
    CompanyName       = 'wbaamaral'
    Copyright         = '(c) wbaamaral. All rights reserved.'
    Description       = 'Helpers seguros para diagnóstico e operação do licenciamento Windows.'
    PowerShellVersion = '5.1'
    RequiredModules   = @(
        @{ ModuleName = 'WbaToolkit.Core'; ModuleVersion = '1.0.0' }
    )
    FunctionsToExport = @(
        'Backup-LicenseState',
        'Get-LicenseCycleStatus',
        'Get-WindowsLicenseInfo',
        'Resolve-LicenseError',
        'Restore-LicenseState'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('WBA', 'Windows', 'Licensing', 'slmgr') } }
}
