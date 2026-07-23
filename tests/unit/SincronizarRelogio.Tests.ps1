#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $script:repoRoot = Get-XtudoRepoRoot
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/sincronizar-relogio.ps1'
    $script:functionPath = Join-Path $script:repoRoot 'modules/WbaToolkit.Maintenance/Public/Sync-ComputerTime.ps1'
    $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    $script:functionContent = Get-Content -LiteralPath $script:functionPath -Raw
    $script:launcherContent = Get-Content -LiteralPath (Join-Path $script:repoRoot 'xtudo.ps1') -Raw
    $script:maintenanceManifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1') -Raw
}

Describe 'Sincronização de relógio' {
    It 'mantém o script oficial e a função no módulo de manutenção' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
        Test-Path -LiteralPath $script:functionPath | Should -BeTrue
        $script:maintenanceManifest | Should -Match "'Sync-ComputerTime'"
    }

    It 'usa diagnóstico sem alteração por padrão e correção explícita' {
        $script:functionContent | Should -Match '\[switch\]\$Apply'
        $script:scriptContent | Should -Match '\[switch\]\$Corrigir'
        $script:scriptContent | Should -Match 'Test-IsAdministrator'
    }

    It 'separa hierarquia AD de NTP externo' {
        $script:functionContent | Should -Match 'PartOfDomain'
        $script:functionContent | Should -Match 'syncfromflags:domhier'
        $script:functionContent | Should -Match 'pool\.ntp\.br'
        $script:functionContent | Should -Match 'time\.windows\.com'
    }

    It 'protege o fuso contra alteração implícita' {
        $script:functionContent | Should -Match 'TimeZoneId'
        $script:functionContent | Should -Match 'Get-TimeZone -ListAvailable'
        $script:functionContent | Should -Match 'Set-TimeZone -Id'
        $script:scriptContent | Should -Match '\$TimeZoneId'
        $script:scriptContent | Should -Match '\$Corrigir'
    }

    It 'expõe a ferramenta no launcher' {
        $script:launcherContent | Should -Match "Path\s+=\s+'scripts/sincronizar-relogio\.ps1'"
        $script:launcherContent | Should -Match "Label\s+=\s+'Sincronizar relógio'"
        $script:launcherContent | Should -Match "'w32time'"
    }

    It 'mantém a saída de relatórios no padrão do toolkit' {
        $script:scriptContent | Should -Match 'Initialize-ToolkitReportSession'
        $script:scriptContent | Should -Match 'sincronizar-relogio\.json'
        $script:scriptContent | Should -Match 'sincronizar-relogio\.txt'
        $script:scriptContent | Should -Match 'sincronizar-relogio\.html'
    }
}
