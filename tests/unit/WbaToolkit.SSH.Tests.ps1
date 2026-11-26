#requires -version 5.1

# BCK-065/A-SSH-1: Set-SshdConfig respeita blocos Match, grava sem BOM e valida com sshd -t.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
    Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.SSH\WbaToolkit.SSH.psd1') -Force

    $script:defaultConfig = @(
        '# sshd_config padrao do OpenSSH para Windows (resumo)'
        '#Port 22'
        'AuthorizedKeysFile .ssh/authorized_keys'
        'PasswordAuthentication yes'
        'Subsystem sftp sftp-server.exe'
        ''
        'Match Group administrators'
        '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
    ) -join "`r`n"
}

Describe 'Set-SshdConfig' {
    BeforeEach {
        $script:configPath = Join-Path $TestDrive ("sshd_config_{0}" -f [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($script:configPath, $script:defaultConfig + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
        Mock -ModuleName WbaToolkit.SSH Test-SshdConfigSyntax { [pscustomobject]@{ Available = $true; Valid = $true; Output = '' } }
    }

    It 'Insere diretiva nova antes do primeiro Match e preserva o bloco' {
        $r = Set-SshdConfig -Settings @{ PubkeyAuthentication = 'yes' } -Path $script:configPath -Confirm:$false

        $r.Success | Should -BeTrue
        $lines = [System.IO.File]::ReadAllLines($script:configPath)
        $matchAt = [array]::IndexOf($lines, 'Match Group administrators')
        $newAt = [array]::IndexOf($lines, 'PubkeyAuthentication yes')
        $newAt | Should -BeGreaterOrEqual 0
        $newAt | Should -BeLessThan $matchAt
        $lines[-1] | Should -Match 'administrators_authorized_keys'
    }

    It 'Altera so a diretiva global, nao a de dentro do Match' {
        Set-SshdConfig -Settings @{ AuthorizedKeysFile = '.ssh/outra' } -Path $script:configPath -Confirm:$false | Out-Null

        $content = [System.IO.File]::ReadAllText($script:configPath)
        $content | Should -Match '(?m)^AuthorizedKeysFile \.ssh/outra\r?$'
        $content | Should -Match 'AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
    }

    It 'Grava UTF-8 sem BOM e preserva CRLF' {
        Set-SshdConfig -Settings @{ PasswordAuthentication = 'no' } -Path $script:configPath -Confirm:$false | Out-Null

        $bytes = [System.IO.File]::ReadAllBytes($script:configPath)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        [System.IO.File]::ReadAllText($script:configPath) | Should -Match "PasswordAuthentication no`r`n"
    }

    It 'Restaura o backup quando sshd -t rejeita a configuracao' {
        Mock -ModuleName WbaToolkit.SSH Test-SshdConfigSyntax { [pscustomobject]@{ Available = $true; Valid = $false; Output = 'Bad configuration option' } }
        $before = [System.IO.File]::ReadAllText($script:configPath)

        $r = Set-SshdConfig -Settings @{ OpcaoInvalida = 'x' } -Path $script:configPath -Confirm:$false

        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'sshd -t'
        [System.IO.File]::ReadAllText($script:configPath) | Should -Be $before
    }
}
