#requires -version 5.1

Describe 'Excecoes documentadas de supressao de erro' {
    It 'mantem cada SilentlyContinue rastreado por BCK-056' {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $manifestPath = Join-Path $repoRoot 'quality/error-suppression-exceptions.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

        $manifest.Task | Should -Be 'BCK-056'
        $manifest.SchemaVersion | Should -Be 1

        $actual = @{}
        Get-ChildItem (Join-Path $repoRoot 'scripts'), (Join-Path $repoRoot 'modules') -Recurse -File -Include '*.ps1', '*.psm1' |
            Select-String -Pattern '-ErrorAction\s+SilentlyContinue' |
            Group-Object Path | ForEach-Object {
                $relative = $_.Name.Substring($repoRoot.Length + 1).Replace('\', '/')
                $actual[$relative] = $_.Count
            }

        $expected = @{}
        foreach ($exception in $manifest.Exceptions) {
            $exception.Reason | Should -Not -BeNullOrEmpty
            $expected[$exception.Path] = [int]$exception.Count
        }

        $actual.Keys | Sort-Object | Should -Be ($expected.Keys | Sort-Object)
        foreach ($path in $expected.Keys) {
            $actual[$path] | Should -Be $expected[$path]
        }
    }
}
