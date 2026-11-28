#requires -version 5.1

# BCK-070: funcoes publicas do WbaToolkit.Startup sem teste. O store de itens desabilitados e as chaves Run
# ficam no TestRegistry do Pester; pastas de inicializacao no TestDrive; tarefas agendadas sao simuladas.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.Startup\WbaToolkit.Startup.psd1') -Force

    function script:New-TestStartupItem {
        param([hashtable]$Parameters)
        & (Get-Module WbaToolkit.Startup) { param($p) ConvertTo-StartupItem @p } $Parameters
    }

    function script:Set-StartupMocks {
        Mock -ModuleName WbaToolkit.Startup Get-StartupStorePath { 'TestRegistry:\Store' }
        Mock -ModuleName WbaToolkit.Startup Get-StartupDisabledRoot { Join-Path $TestDrive 'Disabled' }
        Mock -ModuleName WbaToolkit.Startup Write-Ok { }
        Mock -ModuleName WbaToolkit.Startup Write-Warn { }
        Mock -ModuleName WbaToolkit.Startup Write-Info { }
        Mock -ModuleName WbaToolkit.Startup Disable-ScheduledTask { }
        Mock -ModuleName WbaToolkit.Startup Enable-ScheduledTask { }
        Mock -ModuleName WbaToolkit.Startup Unregister-ScheduledTask { }
        Mock -ModuleName WbaToolkit.Startup Get-RegistryStartupItems { @() }
        Mock -ModuleName WbaToolkit.Startup Get-StartupFolderItems { @() }
        Mock -ModuleName WbaToolkit.Startup Get-LogonStartupTaskItems { @() }
    }
}

Describe 'Disable-StartupItem e Enable-StartupItem' {
    BeforeEach {
        Set-StartupMocks
        Remove-Item -LiteralPath 'TestRegistry:\Run', 'TestRegistry:\Store' -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path 'TestRegistry:\Run' -Force | Out-Null
        New-ItemProperty -Path 'TestRegistry:\Run' -Name 'Outro' -Value 'outro.exe' -PropertyType String | Out-Null
        New-ItemProperty -Path 'TestRegistry:\Run' -Name 'App' -Value '%ProgramFiles%\App\app.exe /min' -PropertyType ExpandString | Out-Null
        $script:regItem = New-TestStartupItem @{
            SourceType = 'Registry'; Scope = 'User'; Location = 'TestRegistry:\Run'; Name = 'App'; ValueName = 'App'
            Command = '%ProgramFiles%\App\app.exe /min'; ValueKind = 'ExpandString'; RawValue = '%ProgramFiles%\App\app.exe /min'
        }
    }

    It 'Registro: desabilita, aparece desligado e reabilita preservando REG_EXPAND_SZ sem expandir' {
        $r = Disable-StartupItem -Item $script:regItem -Confirm:$false

        $r.Success | Should -BeTrue
        (Get-Item -LiteralPath 'TestRegistry:\Run').GetValueNames() | Should -Not -Contain 'App'
        (Get-ItemProperty -LiteralPath 'TestRegistry:\Run').Outro | Should -Be 'outro.exe'

        $desligado = @(Get-StartupItem)
        $desligado.Count | Should -Be 1
        $desligado[0].Enabled | Should -BeFalse
        $desligado[0].ManagedDisabled | Should -BeTrue
        $desligado[0].RawValue | Should -Be '%ProgramFiles%\App\app.exe /min'

        $e = Enable-StartupItem -Item $desligado[0]

        $e.Success | Should -BeTrue
        $chave = Get-Item -LiteralPath 'TestRegistry:\Run'
        $chave.GetValueKind('App') | Should -Be 'ExpandString'
        $chave.GetValue('App', $null, 'DoNotExpandEnvironmentNames') | Should -Be '%ProgramFiles%\App\app.exe /min'
        @(Get-ChildItem -LiteralPath 'TestRegistry:\Store' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'Entrada ja desabilitada nao e alterada' {
        $item = New-TestStartupItem @{ SourceType = 'Registry'; Scope = 'User'; Location = 'TestRegistry:\Run'; Name = 'App'; ValueName = 'App'; Enabled = $false }

        (Disable-StartupItem -Item $item -Confirm:$false).Message | Should -Be 'Ja desabilitada.'
    }

    It '-DryRun e -WhatIf nao alteram nada' {
        (Disable-StartupItem -Item $script:regItem -DryRun).Message | Should -Be 'DryRun.'
        (Disable-StartupItem -Item $script:regItem -WhatIf).Message | Should -Be 'WhatIf.'

        (Get-Item -LiteralPath 'TestRegistry:\Run').GetValueNames() | Should -Contain 'App'
        Test-Path -LiteralPath 'TestRegistry:\Store' | Should -BeFalse
    }

    It 'Pasta de inicializacao: move o atalho para o backup e devolve ao reabilitar' {
        $pasta = Join-Path $TestDrive 'Startup'
        New-Item -Path $pasta -ItemType Directory -Force | Out-Null
        $atalho = Join-Path $pasta 'app.lnk'
        Set-Content -LiteralPath $atalho -Value 'atalho'
        $item = New-TestStartupItem @{ SourceType = 'StartupFolder'; Scope = 'User'; Location = $pasta; Name = 'app.lnk'; ValueName = 'app.lnk'; Command = $atalho }

        (Disable-StartupItem -Item $item -Confirm:$false).Success | Should -BeTrue
        Test-Path -LiteralPath $atalho | Should -BeFalse
        $desligado = @(Get-StartupItem)[0]
        Test-Path -LiteralPath $desligado.BackupPath | Should -BeTrue

        (Enable-StartupItem -Item $desligado).Success | Should -BeTrue
        Get-Content -LiteralPath $atalho | Should -Be 'atalho'
        Test-Path -LiteralPath $desligado.BackupPath | Should -BeFalse
    }

    It 'Tarefa agendada: falha ao desabilitar desfaz o registro no store' {
        Mock -ModuleName WbaToolkit.Startup Disable-ScheduledTask { throw 'Acesso negado' }
        $item = New-TestStartupItem @{ SourceType = 'ScheduledTask'; Scope = 'TaskScheduler'; Location = '\Fabricante\'; Name = '\Fabricante\Atualizador'; ValueName = 'Atualizador'; Command = 'upd.exe' }

        $r = Disable-StartupItem -Item $item -Confirm:$false

        $r.Success | Should -BeFalse
        $r.Message | Should -Be 'Acesso negado'
        @(Get-ChildItem -LiteralPath 'TestRegistry:\Store' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'Tarefa agendada: desabilita e reabilita pelo Agendador' {
        $item = New-TestStartupItem @{ SourceType = 'ScheduledTask'; Scope = 'TaskScheduler'; Location = '\Fabricante\'; Name = '\Fabricante\Atualizador'; ValueName = 'Atualizador'; Command = 'upd.exe' }

        (Disable-StartupItem -Item $item -Confirm:$false).Success | Should -BeTrue
        Should -Invoke -ModuleName WbaToolkit.Startup Disable-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'Atualizador' -and $TaskPath -eq '\Fabricante\' }

        (Enable-StartupItem -Item @(Get-StartupItem)[0]).Success | Should -BeTrue
        Should -Invoke -ModuleName WbaToolkit.Startup Enable-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'Atualizador' }
        @(Get-ChildItem -LiteralPath 'TestRegistry:\Store' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'Tipo desconhecido vira falha sem excecao' {
        $item = New-TestStartupItem @{ SourceType = 'Outro'; Scope = 'X'; Location = 'X'; Name = 'X' }

        (Disable-StartupItem -Item $item -Confirm:$false).Success | Should -BeFalse
    }

    It 'Enable recusa entrada ja habilitada' {
        (Enable-StartupItem -Item $script:regItem).Message | Should -Be 'Ja habilitada.'
    }

    It 'Enable de atalho sem backup falha com mensagem' {
        $item = New-TestStartupItem @{ SourceType = 'StartupFolder'; Scope = 'User'; Location = $TestDrive; Name = 'x.lnk'; ValueName = 'x.lnk'; Enabled = $false; ManagedDisabled = $true; BackupPath = (Join-Path $TestDrive 'sumiu.lnk') }

        $r = Enable-StartupItem -Item $item
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'Backup do atalho nao encontrado'
    }
}

Describe 'Remove-StartupItem' {
    BeforeEach {
        Set-StartupMocks
        Remove-Item -LiteralPath 'TestRegistry:\Run', 'TestRegistry:\Store' -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path 'TestRegistry:\Run' -Force | Out-Null
        New-ItemProperty -Path 'TestRegistry:\Run' -Name 'App' -Value 'app.exe' -PropertyType String | Out-Null
        $script:regItem = New-TestStartupItem @{ SourceType = 'Registry'; Scope = 'User'; Location = 'TestRegistry:\Run'; Name = 'App'; ValueName = 'App'; Command = 'app.exe'; RawValue = 'app.exe' }
        Mock -ModuleName WbaToolkit.Startup Read-Host { 'REMOVER INICIALIZACAO' }
    }

    It 'Sem a frase de confirmacao cancela sem remover' {
        Mock -ModuleName WbaToolkit.Startup Read-Host { 'sim' }

        @(Remove-StartupItem -Item $script:regItem).Count | Should -Be 0
        (Get-Item -LiteralPath 'TestRegistry:\Run').GetValueNames() | Should -Contain 'App'
    }

    It 'Com a frase remove o valor do registro' {
        (Remove-StartupItem -Item $script:regItem).Success | Should -BeTrue

        (Get-Item -LiteralPath 'TestRegistry:\Run').GetValueNames() | Should -Not -Contain 'App'
    }

    It 'Item desabilitado pelo toolkit: remove so o store' {
        Disable-StartupItem -Item $script:regItem -Confirm:$false | Out-Null
        $desligado = @(Get-StartupItem)[0]

        (Remove-StartupItem -Item $desligado).Success | Should -BeTrue

        @(Get-ChildItem -LiteralPath 'TestRegistry:\Store' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'Atalho e tarefa agendada' {
        $atalho = Join-Path $TestDrive 'app.lnk'
        Set-Content -LiteralPath $atalho -Value 'x'
        $folderItem = New-TestStartupItem @{ SourceType = 'StartupFolder'; Scope = 'User'; Location = $TestDrive; Name = 'app.lnk'; ValueName = 'app.lnk'; Command = $atalho }
        $taskItem = New-TestStartupItem @{ SourceType = 'ScheduledTask'; Scope = 'TaskScheduler'; Location = '\F\'; Name = '\F\T'; ValueName = 'T' }

        $r = @(Remove-StartupItem -Item $folderItem, $taskItem)

        @($r | Where-Object Success).Count | Should -Be 2
        Test-Path -LiteralPath $atalho | Should -BeFalse
        Should -Invoke -ModuleName WbaToolkit.Startup Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'T' -and $TaskPath -eq '\F\' }
        Should -Invoke -ModuleName WbaToolkit.Startup Read-Host -Times 1 -Exactly
    }

    It '-DryRun nao pergunta nem remove' {
        (Remove-StartupItem -Item $script:regItem -DryRun).Message | Should -Be 'DryRun.'

        Should -Invoke -ModuleName WbaToolkit.Startup Read-Host -Times 0 -Exactly
        (Get-Item -LiteralPath 'TestRegistry:\Run').GetValueNames() | Should -Contain 'App'
    }
}

Describe 'Get-StartupItem e Show-StartupItem' {
    BeforeEach {
        Set-StartupMocks
    }

    It 'Junta as fontes, prefere o item desabilitado pelo toolkit e ordena' {
        $ativo = New-TestStartupItem @{ SourceType = 'ScheduledTask'; Scope = 'TaskScheduler'; Location = '\F\'; Name = '\F\T'; ValueName = 'T'; Enabled = $false }
        $gerenciado = New-TestStartupItem @{ SourceType = 'ScheduledTask'; Scope = 'TaskScheduler'; Location = '\F\'; Name = '\F\T'; ValueName = 'T'; Enabled = $false; ManagedDisabled = $true }
        Mock -ModuleName WbaToolkit.Startup Get-LogonStartupTaskItems { $ativo }
        Mock -ModuleName WbaToolkit.Startup Get-ManagedDisabledStartupItems { $gerenciado }
        Mock -ModuleName WbaToolkit.Startup Get-RegistryStartupItems {
            New-TestStartupItem @{ SourceType = 'Registry'; Scope = 'User'; Location = 'HKCU:\R'; Name = 'Zeta'; ValueName = 'Zeta' }
            New-TestStartupItem @{ SourceType = 'Registry'; Scope = 'Machine'; Location = 'HKLM:\R'; Name = 'Alfa'; ValueName = 'Alfa' }
        }

        $r = @(Get-StartupItem)

        $r.Count | Should -Be 3
        ($r | ForEach-Object { "$($_.SourceType)/$($_.Scope)/$($_.Name)" }) | Should -Be @('Registry/Machine/Alfa', 'Registry/User/Zeta', 'ScheduledTask/TaskScheduler/\F\T')
        $r[2].ManagedDisabled | Should -BeTrue
    }

    It 'Show-StartupItem numera e mostra estado, origem, escopo e nome' {
        $script:linhas = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName WbaToolkit.Startup Write-Host { $script:linhas.Add([string]$Object) }
        $itens = @(
            New-TestStartupItem @{ SourceType = 'Registry'; Scope = 'User'; Location = 'HKCU:\R'; Name = 'App'; ValueName = 'App' }
            New-TestStartupItem @{ SourceType = 'StartupFolder'; Scope = 'Machine'; Location = 'C:\S'; Name = 'b.lnk'; Enabled = $false }
        )

        Show-StartupItem -Items $itens

        $texto = $script:linhas -join ''
        $texto | Should -Match '\[ 1\] ON  Registry \| User \| App'
        $texto | Should -Match '\[ 2\] OFF StartupFolder \| Machine \| b\.lnk'
    }
}

Describe 'Invoke-StartupManager' {
    BeforeEach {
        Set-StartupMocks
        Mock -ModuleName WbaToolkit.Startup Show-StartupItem { }
        Mock -ModuleName WbaToolkit.Startup Write-Host { }
        $script:item = New-TestStartupItem @{ SourceType = 'Registry'; Scope = 'User'; Location = 'HKCU:\R'; Name = 'App'; ValueName = 'App' }
        Mock -ModuleName WbaToolkit.Startup Get-StartupItem { $script:item }
        Mock -ModuleName WbaToolkit.Startup Disable-StartupItem { [pscustomobject]@{ Name = $Item[0].Name; Action = 'Disable'; Success = $true; DryRun = [bool]$DryRun } }
        Mock -ModuleName WbaToolkit.Startup Enable-StartupItem { }
        Mock -ModuleName WbaToolkit.Startup Remove-StartupItem { }
        $script:respostas = [System.Collections.Generic.Queue[string]]::new()
        Mock -ModuleName WbaToolkit.Startup Read-Host { $script:respostas.Dequeue() }
    }

    It 'Seleciona, executa a acao e devolve o registro da sessao' {
        'x', '9', '1', 'd', '0' | ForEach-Object { $script:respostas.Enqueue($_) }

        $log = @(Invoke-StartupManager -DryRun)

        $log.Count | Should -Be 1
        $log[0].Action | Should -Be 'Disable'
        $log[0].DryRun | Should -BeTrue
        Should -Invoke -ModuleName WbaToolkit.Startup Write-Warn -Times 2 -Exactly -ParameterFilter { $Message -eq 'Opcao invalida.' }
    }

    It 'Voltar nao executa nada' {
        '1', 'V', '' | ForEach-Object { $script:respostas.Enqueue($_) }

        @(Invoke-StartupManager).Count | Should -Be 0
        Should -Invoke -ModuleName WbaToolkit.Startup Disable-StartupItem -Times 0 -Exactly
        Should -Invoke -ModuleName WbaToolkit.Startup Enable-StartupItem -Times 0 -Exactly
        Should -Invoke -ModuleName WbaToolkit.Startup Remove-StartupItem -Times 0 -Exactly
    }

    It 'Sem entradas encerra sem perguntar' {
        Mock -ModuleName WbaToolkit.Startup Get-StartupItem { @() }

        @(Invoke-StartupManager).Count | Should -Be 0
        Should -Invoke -ModuleName WbaToolkit.Startup Read-Host -Times 0 -Exactly
    }
}
