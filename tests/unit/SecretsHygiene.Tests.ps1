#requires -version 5.1

# BCK-064/C9 (ADR 0005): segredos de laboratório são gerados localmente e nunca versionados.

BeforeDiscovery {
    $script:gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe 'Higiene de segredos do repositório' -Skip:(-not $script:gitAvailable) {
    It 'Nenhum arquivo em tests/lab-docker/secrets está versionado' {
        $tracked = @(& git -C $script:repoRoot ls-files -- 'tests/lab-docker/secrets')
        $tracked | Should -BeNullOrEmpty
    }

    It 'A pasta tests/lab-docker/secrets é ignorada pelo git' {
        & git -C $script:repoRoot check-ignore -q -- 'tests/lab-docker/secrets/samba-admin-password'
        $LASTEXITCODE | Should -Be 0
    }

    It 'run-ad-test.sh gera a senha do lab quando ela não existe' {
        $content = Get-Content (Join-Path $script:repoRoot 'tests/lab-docker/run-ad-test.sh') -Raw
        $content | Should -Match 'if \[ ! -s "\$SECRET_FILE" \]'
        $content | Should -Match '/dev/urandom'
    }
}
