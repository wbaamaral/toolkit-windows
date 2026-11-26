#requires -version 5.1

# BCK-065: funcao exportada pelo manifesto precisa estar em Public\ (padrao-modulo e ADR 0032).

BeforeDiscovery {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:manifests = @(Get-ChildItem (Join-Path $root 'modules') -Filter '*.psd1' -Recurse -File |
        Where-Object { $_.BaseName -eq $_.Directory.Name } |
        ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } })
}

Describe 'Exportacoes dos modulos' {
    It '<Name> exporta somente funcoes definidas em Public\' -ForEach $script:manifests {
        $data = Import-PowerShellDataFile -LiteralPath $Path
        $publicDir = Join-Path (Split-Path -Parent $Path) 'Public'
        $publicNames = @(if (Test-Path -LiteralPath $publicDir) {
            Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -Recurse -File | ForEach-Object { $_.BaseName }
        })
        $fora = @($data.FunctionsToExport | Where-Object { $_ -and $_ -ne '*' -and $publicNames -notcontains $_ })
        $fora | Should -BeNullOrEmpty
    }
}
