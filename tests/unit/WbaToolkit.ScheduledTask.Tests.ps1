#requires -version 5.1

# BCK-065: Resolve-ScheduledTask nao pode escolher "a primeira" tarefa parecida.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'modules/WbaToolkit.ScheduledTask/Private/Resolve-ScheduledTask.ps1')
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        function global:Get-ScheduledTask { param($TaskName, $TaskPath) }
    }

    function script:New-FakeTask([string]$Path, [string]$Name) {
        [pscustomobject]@{ TaskPath = $Path; TaskName = $Name }
    }
}

Describe 'Resolve-ScheduledTask' {
    BeforeEach {
        $script:all = @(
            New-FakeTask '\WBA\' 'Backup Diario'
            New-FakeTask '\WBA\' 'Backup Semanal'
            New-FakeTask '\Microsoft\Windows\Defrag\' 'ScheduledDefrag'
        )
        Mock Get-ScheduledTask -ParameterFilter { $TaskName } {
            $alvo = [System.Management.Automation.WildcardPattern]::new($TaskName, 'IgnoreCase')
            @($script:all | Where-Object { $alvo.IsMatch($_.TaskName) })
        }
        Mock Get-ScheduledTask -ParameterFilter { -not $TaskName } { $script:all }
    }

    It 'Devolve a tarefa com nome exato' {
        (Resolve-ScheduledTask -TaskName 'Backup Diario').TaskName | Should -Be 'Backup Diario'
    }

    It 'Trata curinga no nome como texto, sem escolher uma tarefa qualquer' {
        Resolve-ScheduledTask -TaskName 'Backup*' | Should -BeNullOrEmpty
    }

    It 'Recusa correspondencia parcial ambigua' {
        { Resolve-ScheduledTask -TaskName 'Backup' } | Should -Throw '*Backup Diario*Backup Semanal*'
    }

    It 'Aceita correspondencia parcial unica' {
        (Resolve-ScheduledTask -TaskName 'Defrag').TaskName | Should -Be 'ScheduledDefrag'
    }

    It 'Devolve nada quando nao ha correspondencia' {
        Resolve-ScheduledTask -TaskName 'Inexistente' | Should -BeNullOrEmpty
    }
}
