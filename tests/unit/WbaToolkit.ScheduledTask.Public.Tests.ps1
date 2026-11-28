#requires -version 5.1

# BCK-070: funcoes publicas do WbaToolkit.ScheduledTask sem teste. As tarefas sao objetos reais de
# New-ScheduledTask (CimInstance com gatilhos e principal), nunca registrados; os cmdlets do Agendador
# que leem ou alteram o sistema sao simulados.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.ScheduledTask\WbaToolkit.ScheduledTask.psd1') -Force

    function script:New-FakeScheduledTask {
        param(
            [string]$Path,
            [string]$Name,
            [int]$State = 3,
            [switch]$Disabled,
            [string]$Description = '',
            $Trigger,
            $Principal
        )
        $settings = if ($Disabled) { New-ScheduledTaskSettingsSet -Disable } else { New-ScheduledTaskSettingsSet }
        $params = @{
            Action      = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c echo ok' -WorkingDirectory 'C:\'
            Settings    = $settings
        }
        if ($Description) { $params['Description'] = $Description }
        if ($Trigger) { $params['Trigger'] = $Trigger }
        if ($Principal) { $params['Principal'] = $Principal }
        $task = New-ScheduledTask @params
        $task.CimInstanceProperties['TaskName'].Value = $Name
        $task.CimInstanceProperties['TaskPath'].Value = $Path
        $task.CimInstanceProperties['State'].Value = $State
        $task
    }

    $script:taskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Copia diaria</Description>
    <URI>\WBA\Backup Diario</URI>
  </RegistrationInfo>
  <Actions Context="Author"><Exec><Command>cmd.exe</Command></Exec></Actions>
</Task>
'@
}

Describe 'Funcoes publicas do WbaToolkit.ScheduledTask' {
    BeforeEach {
        $script:all = @(
            New-FakeScheduledTask '\WBA\' 'Backup Diario' -Description 'Copia diaria dos dados' -Trigger @(
                New-ScheduledTaskTrigger -Once -At '2026-12-01 08:00' -RepetitionInterval (New-TimeSpan -Hours 1)
                New-ScheduledTaskTrigger -AtLogOn -User 'WBA\fulano'
                $(New-ScheduledTaskTrigger -AtStartup | ForEach-Object { $_.Delay = 'PT5M'; $_ })
            ) -Principal (New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545')
            New-FakeScheduledTask '\WBA\' 'Limpeza' -State 1 -Disabled
            New-FakeScheduledTask '\Microsoft\Windows\Defrag\' 'ScheduledDefrag' -State 4
        )
        $script:infos = @{
            'Backup Diario'   = [pscustomobject]@{ LastRunTime = [datetime]'2026-11-26 08:00'; LastTaskResult = 0; NextRunTime = [datetime]'2026-11-27 08:00'; NumberOfMissedRuns = 0 }
            'Limpeza'         = [pscustomobject]@{ LastRunTime = [datetime]'2026-11-20 10:00'; LastTaskResult = 1; NextRunTime = $null; NumberOfMissedRuns = 2 }
            'ScheduledDefrag' = [pscustomobject]@{ LastRunTime = [datetime]'2026-11-25 03:00'; LastTaskResult = 2147942402; NextRunTime = $null; NumberOfMissedRuns = 0 }
        }

        Mock -ModuleName WbaToolkit.ScheduledTask Get-ScheduledTask {
            $lista = $script:all
            if ($TaskPath) { $lista = @($lista | Where-Object { $_.TaskPath -eq $TaskPath }) }
            if ($TaskName) {
                $alvo = [System.Management.Automation.WildcardPattern]::new($TaskName, 'IgnoreCase')
                $lista = @($lista | Where-Object { $alvo.IsMatch($_.TaskName) })
            }
            $lista
        }
        Mock -ModuleName WbaToolkit.ScheduledTask Get-ScheduledTaskInfo { $script:infos[$TaskName] }
        Mock -ModuleName WbaToolkit.ScheduledTask Enable-ScheduledTask { }
        Mock -ModuleName WbaToolkit.ScheduledTask Disable-ScheduledTask { }
        Mock -ModuleName WbaToolkit.ScheduledTask Unregister-ScheduledTask { }
        Mock -ModuleName WbaToolkit.ScheduledTask Export-ScheduledTask { $script:taskXml }
        Mock -ModuleName WbaToolkit.ScheduledTask Register-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath } }
    }

    Context 'Get-ScheduledTaskDetail' {
        It 'Detalha gatilhos com inicio, intervalo, atraso e usuario' {
            $d = Get-ScheduledTaskDetail -TaskName 'Backup Diario'

            $d.TaskPath | Should -Be '\WBA\'
            $d.State | Should -Be 'Ready'
            $d.Description | Should -Be 'Copia diaria dos dados'
            $tempo = $d.Triggers | Where-Object Type -eq 'MSFT_TaskTimeTrigger'
            ([datetime]$tempo.StartBoundary).ToUniversalTime() | Should -Be ([datetime]'2026-12-01 08:00').ToUniversalTime()
            $tempo.Interval | Should -Be 'PT1H'
            ($d.Triggers | Where-Object Type -eq 'MSFT_TaskBootTrigger').Delay | Should -Be 'PT5M'
            ($d.Triggers | Where-Object Type -eq 'MSFT_TaskLogonTrigger').UserId | Should -Be 'WBA\fulano'
        }

        It 'Mostra o grupo como executor quando a tarefa roda por GroupId' {
            $grupo = ([System.Security.Principal.SecurityIdentifier]'S-1-5-32-545').Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]

            (Get-ScheduledTaskDetail -TaskName 'Backup Diario').RunAs | Should -Be $grupo
        }

        It 'Le acoes, execucao manual permitida e historico da ultima execucao' {
            $d = Get-ScheduledTaskDetail -TaskName 'Backup Diario'

            $d.Actions.Execute | Should -Be 'cmd.exe'
            $d.Actions.Argument | Should -Be '/c echo ok'
            $d.Actions.WorkDir | Should -Be 'C:\'
            $d.AllowDemand | Should -BeTrue
            $d.LastRunTime | Should -Be ([datetime]'2026-11-26 08:00')
            $d.LastResult | Should -Be 0
        }

        It 'Tarefa inexistente lanca erro' {
            { Get-ScheduledTaskDetail -TaskName 'Nao Existe' } | Should -Throw "*Tarefa 'Nao Existe' nao encontrada*"
        }
    }

    Context 'Find-ScheduledTask' {
        It 'Sem filtros devolve todas' {
            @(Find-ScheduledTask).Count | Should -Be 3
        }

        It 'Filtra por estado' {
            @(Find-ScheduledTask -State Disabled).TaskName | Should -Be @('Limpeza')
            @(Find-ScheduledTask -State Running).TaskName | Should -Be @('ScheduledDefrag')
        }

        It 'Procura o termo no nome, no caminho e na descricao' {
            @(Find-ScheduledTask -SearchTerm 'dados').TaskName | Should -Be @('Backup Diario')
            @(Find-ScheduledTask -SearchTerm 'Defrag').TaskName | Should -Be @('ScheduledDefrag')
            @(Find-ScheduledTask -SearchTerm 'WBA').Count | Should -Be 2
        }

        It 'Repassa a pasta para o Get-ScheduledTask' {
            @(Find-ScheduledTask -TaskPath '\WBA\').Count | Should -Be 2
            Should -Invoke -ModuleName WbaToolkit.ScheduledTask Get-ScheduledTask -ParameterFilter { $TaskPath -eq '\WBA\' }
        }
    }

    Context 'Get-ScheduledTaskSummary' {
        It 'Conta por estado e habilitacao e lista as falhas recentes' {
            $s = Get-ScheduledTaskSummary

            $s.Total | Should -Be 3
            $s.Enabled | Should -Be 2
            $s.Disabled | Should -Be 1
            $s.Ready | Should -Be 1
            $s.Running | Should -Be 1
            ($s.TopPaths | Where-Object Path -eq '\WBA\').Count | Should -Be 2
            @($s.RecentFailures).TaskName | Should -Be @('ScheduledDefrag', 'Limpeza')
        }
    }

    Context 'Enable, Disable e Unregister' {
        It '<Comando> age sobre a tarefa resolvida' -ForEach @(
            @{ Comando = 'Enable-ScheduledTaskByName'; Cmdlet = 'Enable-ScheduledTask'; Texto = 'habilitada' }
            @{ Comando = 'Disable-ScheduledTaskByName'; Cmdlet = 'Disable-ScheduledTask'; Texto = 'desabilitada' }
            @{ Comando = 'Unregister-ScheduledTaskByName'; Cmdlet = 'Unregister-ScheduledTask'; Texto = 'removida' }
        ) {
            $out = & $Comando -TaskName 'Limpeza' -Confirm:$false

            $out | Should -Be "Tarefa 'Limpeza' $Texto."
            Should -Invoke -ModuleName WbaToolkit.ScheduledTask $Cmdlet -Times 1 -Exactly -ParameterFilter { $InputObject.TaskName -eq 'Limpeza' }
        }

        It '<Comando> -WhatIf nao altera nada' -ForEach @(
            @{ Comando = 'Enable-ScheduledTaskByName'; Cmdlet = 'Enable-ScheduledTask' }
            @{ Comando = 'Disable-ScheduledTaskByName'; Cmdlet = 'Disable-ScheduledTask' }
            @{ Comando = 'Unregister-ScheduledTaskByName'; Cmdlet = 'Unregister-ScheduledTask' }
        ) {
            & $Comando -TaskName 'Limpeza' -WhatIf | Should -BeNullOrEmpty

            Should -Invoke -ModuleName WbaToolkit.ScheduledTask $Cmdlet -Times 0 -Exactly
        }

        It 'Tarefa inexistente lanca erro sem alterar nada' {
            { Disable-ScheduledTaskByName -TaskName 'Nao Existe' -Confirm:$false } | Should -Throw '*nao encontrada*'
            Should -Invoke -ModuleName WbaToolkit.ScheduledTask Disable-ScheduledTask -Times 0 -Exactly
        }

        It 'Nome ambiguo lanca erro sem alterar nada' {
            { Unregister-ScheduledTaskByName -TaskName 'WBA' -Confirm:$false } | Should -Throw '*Candidatas*'
            Should -Invoke -ModuleName WbaToolkit.ScheduledTask Unregister-ScheduledTask -Times 0 -Exactly
        }
    }

    Context 'Export-ScheduledTaskXml e Import-ScheduledTaskXml' {
        It 'Exporta em UTF-16 com BOM, como declara o XML, e devolve so o caminho' {
            $destino = Join-Path $TestDrive 'backup.xml'

            $r = @(Export-ScheduledTaskXml -TaskName 'Backup Diario' -OutputPath $destino)

            $r | Should -Be @($destino)
            $bytes = [System.IO.File]::ReadAllBytes($destino)
            ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) | Should -BeTrue
            [System.IO.File]::ReadAllText($destino) | Should -Be $script:taskXml
            Should -Invoke -ModuleName WbaToolkit.ScheduledTask Export-ScheduledTask -ParameterFilter { $TaskName -eq 'Backup Diario' -and $TaskPath -eq '\WBA\' }
        }

        It 'Sem -OutputPath grava na pasta atual com nome seguro' {
            Push-Location $TestDrive
            try {
                $r = Export-ScheduledTaskXml -TaskName 'Backup Diario'
            } finally {
                Pop-Location
            }

            $r | Should -Be (Join-Path $TestDrive 'Backup Diario.xml')
            Test-Path -LiteralPath $r | Should -BeTrue
        }

        It 'Importa o arquivo exportado com nome e pasta do URI' {
            $arquivo = Join-Path $TestDrive 'ida-e-volta.xml'
            Export-ScheduledTaskXml -TaskName 'Backup Diario' -OutputPath $arquivo | Out-Null

            $r = @(Import-ScheduledTaskXml -XmlPath $arquivo)

            $r.Count | Should -Be 1
            $r[0].TaskName | Should -Be 'Backup Diario'
            Should -Invoke -ModuleName WbaToolkit.ScheduledTask Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskName -eq 'Backup Diario' -and $TaskPath -eq '\WBA\' -and $Xml -eq $script:taskXml
            }
        }

        It 'Nome e pasta informados prevalecem sobre o URI' {
            $arquivo = Join-Path $TestDrive 'utf8.xml'
            [System.IO.File]::WriteAllText($arquivo, $script:taskXml, [System.Text.UTF8Encoding]::new($false))

            Import-ScheduledTaskXml -XmlPath $arquivo -TaskName 'Outra' -TaskPath '\Teste\' | Out-Null

            Should -Invoke -ModuleName WbaToolkit.ScheduledTask Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'Outra' -and $TaskPath -eq '\Teste\' }
        }

        It 'Sem URI usa o nome do arquivo na raiz' {
            $arquivo = Join-Path $TestDrive 'Minha Tarefa.xml'
            [System.IO.File]::WriteAllText($arquivo, '<Task><Actions/></Task>')

            Import-ScheduledTaskXml -XmlPath $arquivo | Out-Null

            Should -Invoke -ModuleName WbaToolkit.ScheduledTask Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'Minha Tarefa' -and $TaskPath -eq '\' }
        }

        It 'Arquivo inexistente lanca erro' {
            { Import-ScheduledTaskXml -XmlPath (Join-Path $TestDrive 'nao-existe.xml') } | Should -Throw '*nao encontrado*'
        }

        It 'Falha do registro vira erro, sem objeto de tarefa' {
            Mock -ModuleName WbaToolkit.ScheduledTask Register-ScheduledTask { throw 'acesso negado' }
            $arquivo = Join-Path $TestDrive 'falha.xml'
            [System.IO.File]::WriteAllText($arquivo, $script:taskXml)

            $r = Import-ScheduledTaskXml -XmlPath $arquivo -ErrorVariable erros -ErrorAction SilentlyContinue

            $r | Should -BeNullOrEmpty
            "$erros" | Should -Match 'acesso negado'
        }
    }
}
