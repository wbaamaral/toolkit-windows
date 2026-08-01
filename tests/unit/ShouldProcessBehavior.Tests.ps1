#requires -version 5.1

Describe 'Operacoes mutaveis respeitam WhatIf' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1') -Force
        Import-Module (Join-Path $repoRoot 'modules/WbaToolkit.Services/WbaToolkit.Services.psd1') -Force
        Import-Module (Join-Path $repoRoot 'modules/WbaToolkit.SSH/WbaToolkit.SSH.psd1') -Force
        . (Join-Path $repoRoot 'modules/WbaToolkit.ScheduledTask/Private/Resolve-ScheduledTask.ps1')
        . (Join-Path $repoRoot 'modules/WbaToolkit.ScheduledTask/Public/Start-ScheduledTaskByName.ps1')
    }

    It 'recusa iniciar tarefa agendada quando WhatIf esta ativo' {
        Mock Resolve-ScheduledTask { [pscustomobject]@{ TaskName = 'Unit'; TaskPath = '\\' } }
        Mock Start-ScheduledTask {}

        Start-ScheduledTaskByName -TaskName 'Unit' -WhatIf

        Should -Invoke Start-ScheduledTask -Times 0 -Exactly
    }

    It 'recusa criar arquivo ZIP quando WhatIf esta ativo' {
        InModuleScope WbaToolkit.Core {
            Mock Test-Path { $true }
            Mock New-Item {}
            Mock Remove-Item {}
            Mock Compress-Archive {}

            New-ToolkitArchive -SourcePath 'C:\origem' -DestinationPath 'C:\saida\backup.zip' -WhatIf | Out-Null

            Should -Invoke New-Item -Times 0 -Exactly
            Should -Invoke Remove-Item -Times 0 -Exactly
            Should -Invoke Compress-Archive -Times 0 -Exactly
        }
    }

    It 'recusa iniciar servico quando WhatIf esta ativo' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope WbaToolkit.Services {
            Mock Test-IsAdministrator { $true }
            Mock Resolve-WindowsService { [pscustomobject]@{ Exists = $true; Service = [pscustomobject]@{ Status = 'Stopped' }; Message = $null } }
            Mock Start-Service {}

            Start-WindowsService -Name 'UnitService' -WhatIf | Out-Null

            Should -Invoke Start-Service -Times 0 -Exactly
        }
    }

    It 'recusa alterar sshd_config quando WhatIf esta ativo' {
        InModuleScope WbaToolkit.SSH {
            Mock Test-Path { $true }
            Mock Copy-Item {}
            Mock Set-Content {}

            Set-SshdConfig -Settings @{ Port = '2222' } -Path 'C:\ProgramData\ssh\sshd_config' -WhatIf | Out-Null

            Should -Invoke Copy-Item -Times 0 -Exactly
            Should -Invoke Set-Content -Times 0 -Exactly
        }
    }

    It 'documenta impactos altos para operacoes irreversiveis' {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        foreach ($path in @(
            'modules/WbaToolkit.Services/Public/Stop-WindowsService.ps1',
            'modules/WbaToolkit.SSH/Public/New-SshHostKey.ps1',
            'modules/WbaToolkit.SSH/Public/Remove-SshAuthorizedKey.ps1',
            'scripts/remover-perfis-inativos.ps1',
            'scripts/configurar-acesso-remoto.ps1'
        )) {
            (Get-Content -LiteralPath (Join-Path $repoRoot $path) -Raw) | Should -Match "ConfirmImpact\s*=\s*'High'"
        }
    }
}
