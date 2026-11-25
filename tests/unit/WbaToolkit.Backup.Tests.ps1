#requires -version 5.1

Describe 'Remove-BackupAntigo (BCK-063 / C5)' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.Backup\WbaToolkit.Backup.psd1') -Force

        # Grava metadados.json com CreatedAt no formato que o Windows PowerShell 5.1
        # produz para Get-Date: objeto {value, DisplayHint, DateTime}.
        function New-SessionPs51 {
            param([string]$Path, [datetime]$CreatedAt)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $epochMs = ([System.DateTimeOffset]$CreatedAt).ToUnixTimeMilliseconds()
            $json = '{ "CreatedAt": { "value": "\/Date(' + $epochMs + ')\/", "DisplayHint": 2, "DateTime": "x" } }'
            [System.IO.File]::WriteAllText((Join-Path $Path 'metadados.json'), $json)
        }

        function New-SessionIso {
            param([string]$Path, [datetime]$CreatedAt)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $json = '{ "CreatedAt": "' + $CreatedAt.ToString('o') + '" }'
            [System.IO.File]::WriteAllText((Join-Path $Path 'metadados.json'), $json)
        }
    }

    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:container = Join-Path $script:root 'userdata'
        New-Item -ItemType Directory -Path $script:container -Force | Out-Null
        # O conteiner e antigo: o bug original o removia pela CreationTime.
        (Get-Item -LiteralPath $script:container).CreationTime = (Get-Date).AddDays(-400)
    }

    It 'Remove apenas a sessao antiga e preserva o conteiner e a sessao recente' {
        $old = Join-Path $script:container '01012026_100000'
        $new = Join-Path $script:container '20112026_100000'
        New-SessionPs51 -Path $old -CreatedAt (Get-Date).AddDays(-60)
        New-SessionPs51 -Path $new -CreatedAt (Get-Date).AddDays(-1)

        $out = Remove-BackupAntigo -Days 30 -BackupRoot $script:root -Confirm:$false

        Test-Path -LiteralPath $old | Should -BeFalse
        Test-Path -LiteralPath $new | Should -BeTrue
        Test-Path -LiteralPath $script:container | Should -BeTrue
        ($out -join ' ') | Should -Match '^1 backup'
    }

    It 'Aceita CreatedAt em ISO 8601' {
        $old = Join-Path $script:container 'iso-antigo'
        New-SessionIso -Path $old -CreatedAt (Get-Date).AddDays(-90)

        Remove-BackupAntigo -Days 30 -BackupRoot $script:root -Confirm:$false | Out-Null

        Test-Path -LiteralPath $old | Should -BeFalse
    }

    It 'Nunca remove diretorio sem metadados, mesmo antigo' {
        $semMeta = Join-Path $script:container 'sem-metadados'
        New-Item -ItemType Directory -Path $semMeta -Force | Out-Null
        (Get-Item -LiteralPath $semMeta).CreationTime = (Get-Date).AddDays(-400)

        $out = Remove-BackupAntigo -Days 30 -BackupRoot $script:root -Confirm:$false

        Test-Path -LiteralPath $semMeta | Should -BeTrue
        ($out -join ' ') | Should -Match 'Nenhum backup antigo'
    }

    It 'Reconhece sessao legada no primeiro nivel sem descer nela' {
        $legacy = Join-Path $script:root 'sessao-legada'
        New-SessionPs51 -Path $legacy -CreatedAt (Get-Date).AddDays(-60)
        New-SessionPs51 -Path (Join-Path $legacy 'data') -CreatedAt (Get-Date).AddDays(-60)

        $out = Remove-BackupAntigo -Days 30 -BackupRoot $script:root -Confirm:$false

        Test-Path -LiteralPath $legacy | Should -BeFalse
        ($out -join ' ') | Should -Match '^1 backup'
    }

    It 'Nao remove nada com -WhatIf' {
        $old = Join-Path $script:container '01012026_100000'
        New-SessionPs51 -Path $old -CreatedAt (Get-Date).AddDays(-60)

        Remove-BackupAntigo -Days 30 -BackupRoot $script:root -WhatIf | Out-Null

        Test-Path -LiteralPath $old | Should -BeTrue
    }
}
