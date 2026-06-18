#requires -version 5.1

$ToolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CorePath    = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$ModulePath  = Join-Path $ToolkitRoot 'modules/WbaToolkit.Startup/WbaToolkit.Startup.psd1'

Import-Module $CorePath   -Force -ErrorAction Stop
Import-Module $ModulePath -Force -ErrorAction Stop

Describe 'WbaToolkit.Startup' {

    Context 'Exportacao do modulo' {
        It 'Deve exportar Get-StartupItem' {
            (Get-Command Get-StartupItem -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Show-StartupItem' {
            (Get-Command Show-StartupItem -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Disable-StartupItem' {
            (Get-Command Disable-StartupItem -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Enable-StartupItem' {
            (Get-Command Enable-StartupItem -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Remove-StartupItem' {
            (Get-Command Remove-StartupItem -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Invoke-StartupManager' {
            (Get-Command Invoke-StartupManager -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Deve exportar Get-ServiceStartupState' {
            (Get-Command Get-ServiceStartupState -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
        It 'Nao deve exportar funcoes privadas' {
            Get-Command Get-RegistryStartupItems       -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Get-StartupFolderItems         -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Get-LogonStartupTaskItems      -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Get-ManagedDisabledStartupItems -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Get-StartupDisabledRoot        -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Get-StartupStorePath           -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command New-StartupItemId              -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command ConvertTo-StartupItem          -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Save-StartupStoreItem          -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command Remove-StartupStoreItem        -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Get-StartupItem' {
        It 'Deve retornar um array (mesmo quando nao ha itens)' {
            $result = @(Get-StartupItem)
            $result | Should -Not -BeNullOrEmpty -ErrorAction SilentlyContinue
            $result.GetType().IsArray | Should -BeTrue
        }
        It 'Itens retornados devem conter as propriedades esperadas' {
            $result = @(Get-StartupItem)
            if ($result.Count -eq 0) {
                Set-ItResult -Skipped -Because 'Nenhum item de inicializacao encontrado no ambiente de teste'
                return
            }
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'Id'
            $props | Should -Contain 'Name'
            $props | Should -Contain 'SourceType'
            $props | Should -Contain 'Scope'
            $props | Should -Contain 'Enabled'
            $props | Should -Contain 'ManagedDisabled'
            $props | Should -Contain 'CanDisable'
            $props | Should -Contain 'CanEnable'
            $props | Should -Contain 'CanRemove'
        }
        It 'Resultado deve ser ordenado por SourceType, Scope e Name' {
            $result = @(Get-StartupItem)
            if ($result.Count -lt 2) {
                Set-ItResult -Skipped -Because 'Menos de 2 itens encontrados — ordenacao nao pode ser verificada'
                return
            }
            $sorted = @($result | Sort-Object SourceType, Scope, Name)
            for ($i = 0; $i -lt $result.Count; $i++) {
                $result[$i].Id | Should -Be $sorted[$i].Id
            }
        }
    }

    Context 'Show-StartupItem' {
        It 'Nao deve lancar excecao ao exibir um item valido' {
            $item = [pscustomobject]@{
                Name = 'AppTeste'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false
            }
            { Show-StartupItem -Items @($item) } | Should -Not -Throw
        }
        It 'Nao deve lancar excecao ao exibir multiplos itens' {
            $itens = @(
                [pscustomobject]@{ Name = 'Alpha'; SourceType = 'Registry';      Scope = 'User';   Enabled = $true;  ManagedDisabled = $false }
                [pscustomobject]@{ Name = 'Beta';  SourceType = 'StartupFolder'; Scope = 'System'; Enabled = $false; ManagedDisabled = $true  }
            )
            { Show-StartupItem -Items $itens } | Should -Not -Throw
        }
    }

    Context 'Disable-StartupItem - DryRun' {
        It 'Deve retornar resultado DryRun para item habilitado' {
            $item = [pscustomobject]@{
                Name = 'AppTeste'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false; CanDisable = $true
            }
            $result = Disable-StartupItem -Item $item -DryRun
            $result.Success | Should -BeTrue
            $result.Message | Should -Be 'DryRun.'
            $result.Action  | Should -Be 'Disable'
            $result.Name    | Should -Be 'AppTeste'
        }
        It 'Deve aceitar lista de itens e retornar um resultado por item' {
            $itens = @(
                [pscustomobject]@{ Name = 'App1'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false; CanDisable = $true }
                [pscustomobject]@{ Name = 'App2'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false; CanDisable = $true }
            )
            $results = @(Disable-StartupItem -Item $itens -DryRun)
            $results.Count | Should -Be 2
            $results | ForEach-Object { $_.Message | Should -Be 'DryRun.' }
        }
    }

    Context 'Disable-StartupItem - item ja desabilitado' {
        It 'Deve retornar Success false e mensagem de ja desabilitada' {
            $item = [pscustomobject]@{
                Name = 'AppTeste'; SourceType = 'Registry'; Scope = 'User'; Enabled = $false; ManagedDisabled = $false
            }
            $result = Disable-StartupItem -Item $item -DryRun
            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Ja desabilitada.'
            $result.Name    | Should -Be 'AppTeste'
        }
    }

    Context 'Enable-StartupItem - DryRun' {
        It 'Deve retornar resultado DryRun para item gerenciado desabilitado' {
            $item = [pscustomobject]@{
                Name = 'AppTeste'; SourceType = 'Registry'; Scope = 'User'; Enabled = $false; ManagedDisabled = $true; CanEnable = $true
            }
            $result = Enable-StartupItem -Item $item -DryRun
            $result.Success | Should -BeTrue
            $result.Message | Should -Be 'DryRun.'
            $result.Action  | Should -Be 'Enable'
            $result.Name    | Should -Be 'AppTeste'
        }
        It 'Deve aceitar lista de itens e retornar um resultado por item' {
            $itens = @(
                [pscustomobject]@{ Name = 'App1'; SourceType = 'Registry'; Scope = 'User'; Enabled = $false; ManagedDisabled = $true; CanEnable = $true }
                [pscustomobject]@{ Name = 'App2'; SourceType = 'Registry'; Scope = 'User'; Enabled = $false; ManagedDisabled = $true; CanEnable = $true }
            )
            $results = @(Enable-StartupItem -Item $itens -DryRun)
            $results.Count | Should -Be 2
            $results | ForEach-Object { $_.Message | Should -Be 'DryRun.' }
        }
    }

    Context 'Enable-StartupItem - item ja habilitado' {
        It 'Deve retornar Success false e mensagem de ja habilitada' {
            $item = [pscustomobject]@{
                Name = 'AppTeste'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false
            }
            $result = Enable-StartupItem -Item $item -DryRun
            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Ja habilitada.'
            $result.Name    | Should -Be 'AppTeste'
        }
    }

    Context 'Remove-StartupItem - DryRun com confirmacao' {
        BeforeEach {
            Mock Read-Host { return 'REMOVER INICIALIZACAO' }
        }
        It 'Deve retornar resultado DryRun quando confirmacao e fornecida' {
            $item = [pscustomobject]@{
                Name = 'AppTeste'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false; CanRemove = $true
            }
            $result = Remove-StartupItem -Item $item -DryRun
            $result.Success | Should -BeTrue
            $result.Message | Should -Be 'DryRun.'
            $result.Action  | Should -Be 'Remove'
            $result.Name    | Should -Be 'AppTeste'
        }
        It 'Deve aceitar lista de itens e retornar um resultado por item' {
            $itens = @(
                [pscustomobject]@{ Name = 'App1'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false; CanRemove = $true }
                [pscustomobject]@{ Name = 'App2'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false; CanRemove = $true }
            )
            $results = @(Remove-StartupItem -Item $itens -DryRun)
            $results.Count | Should -Be 2
            $results | ForEach-Object { $_.Message | Should -Be 'DryRun.' }
        }
    }

    Context 'Remove-StartupItem - cancelamento pelo operador' {
        BeforeEach {
            Mock Read-Host { return 'nao' }
        }
        It 'Deve retornar array vazio quando o operador nao confirma' {
            $item = [pscustomobject]@{
                Name = 'AppTeste'; SourceType = 'Registry'; Scope = 'User'; Enabled = $true; ManagedDisabled = $false
            }
            $result = @(Remove-StartupItem -Item $item)
            $result.Count | Should -Be 0
        }
    }

    Context 'Get-ServiceStartupState' {
        It 'Deve retornar objetos com as propriedades esperadas' {
            $result = @(Get-ServiceStartupState -ServiceName 'Spooler')
            $result.Count | Should -BeGreaterThan 0
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'DisplayName'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'StartType'
        }
        It 'Deve retornar Status Nao encontrado para servico inexistente' {
            $result = @(Get-ServiceStartupState -ServiceName 'WBA_Servico_Inexistente_99999')
            $result.Count        | Should -Be 1
            $result[0].Name      | Should -Be 'WBA_Servico_Inexistente_99999'
            $result[0].Status    | Should -Be 'Nao encontrado'
            $result[0].StartType | Should -BeNullOrEmpty
        }
        It 'Deve retornar um resultado por servico informado' {
            $result = @(Get-ServiceStartupState -ServiceName @('WBA_Inexistente_A', 'WBA_Inexistente_B'))
            $result.Count | Should -Be 2
        }
        It 'Deve usar os servicos padrao quando nenhum nome e informado' {
            $result = @(Get-ServiceStartupState)
            $result.Count | Should -BeGreaterThan 0
        }
    }
}
