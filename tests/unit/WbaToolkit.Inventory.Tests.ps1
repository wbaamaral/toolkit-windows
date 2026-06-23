#requires -version 5.1

BeforeAll {
    . (Join-Path $PSScriptRoot 'Xtudo.TestSupport.ps1')
    $repoRoot = Get-XtudoRepoRoot
    $script:modulePath = Join-Path $repoRoot 'modules/WbaToolkit.Inventory/WbaToolkit.Inventory.psd1'
}

Describe 'Xtudo inventario' {
    It 'Mantem o modulo de inventario carregavel e exportado' {
        Test-Path -LiteralPath $script:modulePath | Should -BeTrue
        Import-Module $script:modulePath -Force
        (Get-Command Get-InventoryCoverageMap -ErrorAction Stop).Name | Should -Be 'Get-InventoryCoverageMap'
    }

    It 'Expõe cobertura completa e lacunas conhecidas' {
        $covered = @(Get-InventoryCoverageMap)
        $covered.Count | Should -Be 12
        ($covered | Where-Object { $_.Status -eq 'Completo' }).Count | Should -Be 11
        ($covered | Where-Object { $_.Status -eq 'Parcial' }).Count | Should -Be 1

        $map = Get-InventoryCoverageMap -IncludeGaps
        $map.Gaps.Count | Should -Be 5
    }
}
