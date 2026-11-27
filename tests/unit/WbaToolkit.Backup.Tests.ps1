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

Describe 'Remove-RestorePoint (BCK-065 / A-BKP-2)' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repoRoot 'modules\WbaToolkit.Backup\WbaToolkit.Backup.psd1') -Force
    }

    BeforeEach {
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint {
            1..3 | ForEach-Object { [pscustomobject]@{ SequenceNumber = $_; CreationTime = '20260101000000.000000-000' } }
        }
    }

    It 'Remove pelo SequenceNumber via SRRemoveRestorePoint, mantendo os mais recentes' {
        Mock -ModuleName WbaToolkit.Backup Invoke-SRRemoveRestorePoint { 0 }

        $out = Remove-RestorePoint -KeepLast 1 -Confirm:$false

        $out | Should -Be '2 de 2 restore point(s) removido(s).'
        Should -Invoke -ModuleName WbaToolkit.Backup Invoke-SRRemoveRestorePoint -Times 1 -Exactly -ParameterFilter { $SequenceNumber -eq 1 }
        Should -Invoke -ModuleName WbaToolkit.Backup Invoke-SRRemoveRestorePoint -Times 1 -Exactly -ParameterFilter { $SequenceNumber -eq 2 }
        Should -Invoke -ModuleName WbaToolkit.Backup Invoke-SRRemoveRestorePoint -Times 0 -Exactly -ParameterFilter { $SequenceNumber -eq 3 }
    }

    It 'Nao reporta sucesso quando a API falha' {
        Mock -ModuleName WbaToolkit.Backup Invoke-SRRemoveRestorePoint { if ($SequenceNumber -eq 2) { 5 } else { 0 } }

        $errs = $null
        $out = Remove-RestorePoint -KeepLast 1 -Confirm:$false -ErrorVariable errs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

        $out | Should -Be '1 de 2 restore point(s) removido(s).'
        @($errs).Count | Should -Be 1
    }

    It '-WhatIf nao remove nada' {
        Mock -ModuleName WbaToolkit.Backup Invoke-SRRemoveRestorePoint { 0 }

        Remove-RestorePoint -All -WhatIf | Out-Null

        Should -Invoke -ModuleName WbaToolkit.Backup Invoke-SRRemoveRestorePoint -Times 0 -Exactly
    }
}

# ---------------------------------------------------------------------------
# BCK-069: cobertura das demais funcoes publicas do modulo. Toda dependencia do
# sistema (rsync, VSS, CIM, restore points, ProgramData) e simulada; nada toca a
# maquina real.
# ---------------------------------------------------------------------------

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'modules\WbaToolkit.Backup\WbaToolkit.Backup.psd1') -Force

    # Grava um config-backup.json no TestDrive apontando o backup e o rsync para la.
    function New-TestBackupConfig {
        param([string]$Root, [int]$RetentionDays = 90)
        $cfg = [pscustomobject]@{
            RestorePoints = [pscustomobject]@{ MaxRestorePoints = 10; MinDiskSpaceGB = 10; RetentionDays = 30; Description = 'Teste' }
            UserBackup    = [pscustomobject]@{
                BackupPaths       = @()
                LocalBackupPath   = (Join-Path $Root 'backups')
                RsyncPath         = (Join-Path $Root 'rsync.exe')
                CompressionEnabled = $true
                RetentionDays     = $RetentionDays
                ExclusionPatterns = @('*.tmp')
            }
        }
        $path = Join-Path $Root 'config-backup.json'
        $cfg | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
        $path
    }

    # Grava metadados.json como o Backup-UserData faz no Windows PowerShell 5.1.
    function New-TestBackupMeta {
        param([string]$Dir, [string]$BackupPath, [datetime]$CreatedAt, [bool]$AllSuccess = $true, [switch]$Iso)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        $created = if ($Iso) {
            '"' + $CreatedAt.ToString('o') + '"'
        } else {
            '{ "value": "\/Date(' + ([System.DateTimeOffset]$CreatedAt).ToUnixTimeMilliseconds() + ')\/", "DisplayHint": 2, "DateTime": "x" }'
        }
        $json = '{ "BackupPath": ' + ($BackupPath | ConvertTo-Json) + ', "SourcePaths": ["a","b"], "CreatedAt": ' + $created + ', "AllSuccess": ' + $AllSuccess.ToString().ToLower() + ' }'
        [System.IO.File]::WriteAllText((Join-Path $Dir 'metadados.json'), $json)
    }
}

Describe 'Get-BackupConfiguration e Set-BackupConfiguration (BCK-069)' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:cfgPath = New-TestBackupConfig -Root $script:root -RetentionDays 7
        $script:oldProgramData = $env:ProgramData
        $env:ProgramData = Join-Path $script:root 'programdata'
    }

    AfterEach { $env:ProgramData = $script:oldProgramData }

    It 'Sem arquivo de configuracao devolve os valores padrao e avisa' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $null }

        $cfg = Get-BackupConfiguration -WarningVariable warn -WarningAction SilentlyContinue

        $cfg.RestorePoints.MaxRestorePoints | Should -Be 10
        $cfg.UserBackup.LocalBackupPath | Should -Be 'C:\WBA\Backups'
        $cfg.UserBackup.RetentionDays | Should -Be 90
        @($warn).Count | Should -Be 1
    }

    It 'Com arquivo devolve o conteudo dele' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $script:cfgPath }

        (Get-BackupConfiguration).UserBackup.RetentionDays | Should -Be 7
    }

    It 'Set atualiza apenas as chaves conhecidas' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $script:cfgPath }

        Set-BackupConfiguration -Settings @{ UserBackup = @{ RetentionDays = 15; ChaveInexistente = 1 } } | Out-Null

        $gravado = Get-Content -Path $script:cfgPath -Raw | ConvertFrom-Json
        $gravado.UserBackup.RetentionDays | Should -Be 15
        $gravado.UserBackup.PSObject.Properties['ChaveInexistente'] | Should -BeNullOrEmpty
    }

    It 'Set sem -Settings nem -Reset falha' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $script:cfgPath }

        { Set-BackupConfiguration } | Should -Throw '*Nenhuma configuracao*'
    }

    It 'Set -WhatIf nao altera o arquivo' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $script:cfgPath }
        $antes = Get-Content -Path $script:cfgPath -Raw

        Set-BackupConfiguration -Settings @{ UserBackup = @{ RetentionDays = 99 } } -WhatIf

        Get-Content -Path $script:cfgPath -Raw | Should -Be $antes
    }

    It 'Reset grava os valores padrao mesmo quando o arquivo ja existe' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $script:cfgPath }

        Set-BackupConfiguration -Reset | Out-Null

        (Get-Content -Path $script:cfgPath -Raw | ConvertFrom-Json).UserBackup.RetentionDays | Should -Be 90
    }

    It 'Sem arquivo, Set cria a configuracao em ProgramData' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $null }

        Set-BackupConfiguration -Settings @{ UserBackup = @{ RetentionDays = 20 } } -WarningAction SilentlyContinue | Out-Null

        $novo = Join-Path $env:ProgramData 'WBA\WindowsToolkit\config-backup.json'
        (Get-Content -Path $novo -Raw | ConvertFrom-Json).UserBackup.RetentionDays | Should -Be 20
    }

    It 'Set -WhatIf sem arquivo nao cria a pasta em ProgramData' {
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $null }

        Set-BackupConfiguration -Settings @{ UserBackup = @{ RetentionDays = 20 } } -WhatIf -WarningAction SilentlyContinue

        Test-Path -LiteralPath (Join-Path $env:ProgramData 'WBA') | Should -BeFalse
    }
}

Describe 'Backup-UserData (BCK-069)' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:cfgPath = New-TestBackupConfig -Root $script:root
        Set-Content -Path (Join-Path $script:root 'rsync.exe') -Value 'fake'
        $script:srcDocs = Join-Path $script:root 'origem\Documentos'
        New-Item -ItemType Directory -Path $script:srcDocs -Force | Out-Null

        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $script:cfgPath }
        Mock -ModuleName WbaToolkit.Backup Write-BackupLog { }
        Mock -ModuleName WbaToolkit.Backup Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'Chama o rsync para cada origem existente e grava os metadados' {
        $faltando = Join-Path $script:root 'origem\NaoExiste'
        $destino = Join-Path $script:root 'destino'

        $meta = Backup-UserData -BackupPath $destino -SourcePaths $script:srcDocs, $faltando

        $meta.AllSuccess | Should -BeTrue
        @($meta.Results).Count | Should -Be 1
        $meta.Results[0].Dest | Should -Be (Join-Path $destino 'Documentos')
        Should -Invoke -ModuleName WbaToolkit.Backup Start-Process -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains "$($script:srcDocs)/") -and ($ArgumentList -contains '--delete')
        }
        Test-Path -LiteralPath (Join-Path $destino 'metadados.json') | Should -BeTrue
    }

    It 'Marca falha quando o rsync retorna codigo diferente de zero' {
        Mock -ModuleName WbaToolkit.Backup Start-Process { [pscustomobject]@{ ExitCode = 23 } }

        $meta = Backup-UserData -BackupPath (Join-Path $script:root 'destino') -SourcePaths $script:srcDocs

        $meta.AllSuccess | Should -BeFalse
        $meta.Results[0].ExitCode | Should -Be 23
    }

    It 'Falha quando o rsync nao existe' {
        Remove-Item -LiteralPath (Join-Path $script:root 'rsync.exe')

        { Backup-UserData -BackupPath (Join-Path $script:root 'destino') -SourcePaths $script:srcDocs } |
            Should -Throw '*rsync nao encontrado*'
    }

    It 'Falha quando nao ha origem para copiar' {
        Mock -ModuleName WbaToolkit.Backup Resolve-BackupPaths { @() }

        { Backup-UserData -BackupPath (Join-Path $script:root 'destino') } | Should -Throw '*Nenhum caminho fonte*'
    }

    It '-WhatIf nao executa o rsync nem grava metadados' {
        $destino = Join-Path $script:root 'destino'

        Backup-UserData -BackupPath $destino -SourcePaths $script:srcDocs -WhatIf

        Should -Invoke -ModuleName WbaToolkit.Backup Start-Process -Times 0 -Exactly
        Test-Path -LiteralPath $destino | Should -BeFalse
    }
}

Describe 'Restore-UserData (BCK-069)' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:backup = Join-Path $script:root 'backup'
        New-Item -ItemType Directory -Path (Join-Path $script:backup 'Documentos'), (Join-Path $script:backup 'Imagens') -Force | Out-Null
        New-TestBackupMeta -Dir $script:backup -BackupPath $script:backup -CreatedAt (Get-Date)
        $script:alvo = Join-Path $script:root 'perfil'

        Mock -ModuleName WbaToolkit.Backup Get-BackupConfigurationInternal { $null }
        Mock -ModuleName WbaToolkit.Backup Write-BackupLog { }
        Mock -ModuleName WbaToolkit.Backup Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'Restaura cada pasta do backup para o destino' {
        $r = Restore-UserData -BackupPath $script:backup -TargetPath $script:alvo -Confirm:$false -WarningAction SilentlyContinue

        $r.AllSuccess | Should -BeTrue
        @($r.Results).Count | Should -Be 2
        @($r.Results.Dest) | Should -Contain (Join-Path $script:alvo 'Documentos')
        Should -Invoke -ModuleName WbaToolkit.Backup Start-Process -Times 2 -Exactly
    }

    It 'Marca falha quando o rsync retorna erro' {
        Mock -ModuleName WbaToolkit.Backup Start-Process { [pscustomobject]@{ ExitCode = 1 } }

        $r = Restore-UserData -BackupPath $script:backup -TargetPath $script:alvo -Confirm:$false -WarningAction SilentlyContinue

        $r.AllSuccess | Should -BeFalse
    }

    It 'Falha quando o backup nao existe' {
        { Restore-UserData -BackupPath (Join-Path $script:root 'nada') -Confirm:$false } | Should -Throw '*nao encontrado*'
    }

    It 'Falha quando o backup nao tem metadados.json' {
        Remove-Item -LiteralPath (Join-Path $script:backup 'metadados.json')

        { Restore-UserData -BackupPath $script:backup -Confirm:$false } | Should -Throw '*metadados.json*'
    }

    It '-WhatIf nao executa o rsync' {
        Restore-UserData -BackupPath $script:backup -TargetPath $script:alvo -WhatIf -WarningAction SilentlyContinue

        Should -Invoke -ModuleName WbaToolkit.Backup Start-Process -Times 0 -Exactly
    }
}

Describe 'Get-BackupHistory (BCK-069)' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }

    It 'Devolve lista vazia quando a raiz nao existe' {
        @(Get-BackupHistory -BackupRoot (Join-Path $script:root 'nada')).Count | Should -Be 0
    }

    It 'Lista cada backup uma vez, embora o Backup-UserData grave metadados na sessao e em data' {
        $sessao = Join-Path $script:root 'userdata\01112026_100000'
        $data = Join-Path $sessao 'data'
        # Uma unica data: o Backup-UserData grava o mesmo objeto nos dois arquivos.
        $quando = (Get-Date).AddDays(-2)
        New-TestBackupMeta -Dir $sessao -BackupPath $data -CreatedAt $quando
        New-TestBackupMeta -Dir $data -BackupPath $data -CreatedAt $quando

        @(Get-BackupHistory -BackupRoot $script:root).Count | Should -Be 1
    }

    It 'Converte CreatedAt para data e ordena do mais recente para o mais antigo' {
        New-TestBackupMeta -Dir (Join-Path $script:root 'a') -BackupPath 'A' -CreatedAt (Get-Date '2026-01-10')
        New-TestBackupMeta -Dir (Join-Path $script:root 'b') -BackupPath 'B' -CreatedAt (Get-Date '2026-03-10') -Iso
        New-TestBackupMeta -Dir (Join-Path $script:root 'c') -BackupPath 'C' -CreatedAt (Get-Date '2026-02-10')

        $h = @(Get-BackupHistory -BackupRoot $script:root)

        $h.Count | Should -Be 3
        $h[0].CreatedAt | Should -BeOfType [datetime]
        @($h.BackupPath) -join ',' | Should -Be 'B,C,A'
        $h[0].SourceCount | Should -Be 2
    }

    It 'Ignora metadados invalidos' {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'ruim') -Force | Out-Null
        Set-Content -Path (Join-Path $script:root 'ruim\metadados.json') -Value '{ isto nao e json'
        New-TestBackupMeta -Dir (Join-Path $script:root 'bom') -BackupPath 'BOM' -CreatedAt (Get-Date)

        @(Get-BackupHistory -BackupRoot $script:root).BackupPath | Should -Be 'BOM'
    }
}

Describe 'Get-RestorePointInfo (BCK-069)' {
    It 'Converte a data WMI e respeita -LastN' {
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint {
            1..3 | ForEach-Object {
                [pscustomobject]@{ SequenceNumber = $_; Description = "RP$_"; CreationTime = "2026010$($_)103000.000000-000"; RestorePointType = 0; EventType = 100 }
            }
        }

        $rp = @(Get-RestorePointInfo -LastN 2)

        $rp.Count | Should -Be 2
        @($rp.SequenceNumber) -join ',' | Should -Be '2,3'
        $rp[0].CreationTime | Should -BeOfType [datetime]
        $rp[0].Description | Should -Be 'RP2'
    }

    It 'Mantem o valor original quando a data nao e WMI' {
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint {
            [pscustomobject]@{ SequenceNumber = 9; Description = 'X'; CreationTime = 'data-invalida'; RestorePointType = 0; EventType = 100 }
        }

        (Get-RestorePointInfo).CreationTime | Should -Be 'data-invalida'
    }

    It 'Devolve lista vazia e avisa quando a consulta falha' {
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint { throw 'acesso negado' }

        $rp = @(Get-RestorePointInfo -WarningVariable warn -WarningAction SilentlyContinue)

        $rp.Count | Should -Be 0
        @($warn).Count | Should -Be 1
    }
}

Describe 'New-RestorePoint (BCK-069)' {
    It 'Cria o ponto com a descricao e o tipo informados' {
        Mock -ModuleName WbaToolkit.Backup Checkpoint-Computer { }

        $r = New-RestorePoint -Description 'Antes do teste' -RestorePointType MODIFY_SETTINGS | Select-Object -Last 1

        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName WbaToolkit.Backup Checkpoint-Computer -Times 1 -Exactly -ParameterFilter {
            $Description -eq 'Antes do teste' -and $RestorePointType -eq 'MODIFY_SETTINGS'
        }
    }

    It 'Devolve falha e erro quando o Windows recusa' {
        Mock -ModuleName WbaToolkit.Backup Checkpoint-Computer { throw 'limite de 24h' }

        $r = New-RestorePoint -ErrorVariable errs -ErrorAction SilentlyContinue

        $r.Success | Should -BeFalse
        $r.Error | Should -Match 'limite de 24h'
        @($errs).Count | Should -BeGreaterThan 0
    }

    It '-WhatIf nao cria o ponto' {
        Mock -ModuleName WbaToolkit.Backup Checkpoint-Computer { }

        New-RestorePoint -WhatIf

        Should -Invoke -ModuleName WbaToolkit.Backup Checkpoint-Computer -Times 0 -Exactly
    }
}

Describe 'Restore-SystemToPoint (BCK-069)' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.Backup Restore-Computer { }
    }

    It 'Agenda a restauracao do ponto informado' {
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint { [pscustomobject]@{ SequenceNumber = 7; Description = 'RP7' } }

        Restore-SystemToPoint -SequenceNumber 7 -Confirm:$false -WarningAction SilentlyContinue

        Should -Invoke -ModuleName WbaToolkit.Backup Restore-Computer -Times 1 -Exactly -ParameterFilter { $RestorePoint -eq 7 }
    }

    It 'Falha sem tocar no sistema quando o ponto nao existe' {
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint { $null }

        { Restore-SystemToPoint -SequenceNumber 99 -Confirm:$false } | Should -Throw '*nao encontrado*'
        Should -Invoke -ModuleName WbaToolkit.Backup Restore-Computer -Times 0 -Exactly
    }

    It '-WhatIf nao restaura' {
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint { [pscustomobject]@{ SequenceNumber = 7; Description = 'RP7' } }

        Restore-SystemToPoint -SequenceNumber 7 -WhatIf

        Should -Invoke -ModuleName WbaToolkit.Backup Restore-Computer -Times 0 -Exactly
    }
}

Describe 'Test-VssHealth (BCK-069)' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.Backup Get-Service { [pscustomobject]@{ Name = $Name; Status = 'Running' } }
        Mock -ModuleName WbaToolkit.Backup Get-Volume {
            [pscustomobject]@{ DriveType = 'Fixed'; DriveLetter = 'C'; Size = 100GB; SizeRemaining = 50GB }
            [pscustomobject]@{ DriveType = 'Removable'; DriveLetter = 'E'; Size = 8GB; SizeRemaining = 0 }
        }
        Mock -ModuleName WbaToolkit.Backup Get-CimInstance { 1..2 | ForEach-Object { [pscustomobject]@{ Id = $_ } } }
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint { 1..3 | ForEach-Object { [pscustomobject]@{ SequenceNumber = $_ } } }
    }

    It 'Saudavel quando VSS roda e ha espaco; considera so volumes fixos' {
        $r = Test-VssHealth

        $r.Healthy | Should -BeTrue
        @($r.Checks | Where-Object Name -like 'Espaco disco*').Count | Should -Be 1
        ($r.Checks | Where-Object Name -eq 'Shadow Copies existentes').Detail | Should -Match '^2 '
        ($r.Checks | Where-Object Name -eq 'Restore Points existentes').Detail | Should -Match '^3 '
    }

    It 'Nao saudavel quando o servico VSS esta parado' {
        Mock -ModuleName WbaToolkit.Backup Get-Service { [pscustomobject]@{ Name = $Name; Status = 'Stopped' } }

        $r = Test-VssHealth

        $r.Healthy | Should -BeFalse
        ($r.Checks | Where-Object Name -eq 'Servico VSS').Status | Should -Be 'FALHA'
    }

    It 'Classifica o espaco livre em OK, AVISO e FALHA' {
        Mock -ModuleName WbaToolkit.Backup Get-Volume {
            [pscustomobject]@{ DriveType = 'Fixed'; DriveLetter = 'C'; Size = 100GB; SizeRemaining = 20GB }
            [pscustomobject]@{ DriveType = 'Fixed'; DriveLetter = 'D'; Size = 100GB; SizeRemaining = 10GB }
            [pscustomobject]@{ DriveType = 'Fixed'; DriveLetter = 'F'; Size = 100GB; SizeRemaining = 2GB }
        }

        $r = Test-VssHealth

        ($r.Checks | Where-Object Name -eq 'Espaco disco C:').Status | Should -Be 'OK'
        ($r.Checks | Where-Object Name -eq 'Espaco disco D:').Status | Should -Be 'AVISO'
        ($r.Checks | Where-Object Name -eq 'Espaco disco F:').Status | Should -Be 'FALHA'
        $r.Healthy | Should -BeFalse
    }

    It 'Nao quebra quando as consultas do sistema falham' {
        Mock -ModuleName WbaToolkit.Backup Get-Service { throw 'sem servico' }
        Mock -ModuleName WbaToolkit.Backup Get-Volume { throw 'sem volume' }
        Mock -ModuleName WbaToolkit.Backup Get-CimInstance { throw 'sem CIM' }
        Mock -ModuleName WbaToolkit.Backup Get-ComputerRestorePoint { throw 'sem RP' }

        $r = Test-VssHealth

        ($r.Checks | Where-Object Name -eq 'Servico VSS').Detail | Should -Be 'Nao encontrado'
        $r.Healthy | Should -BeFalse
    }
}

Describe 'Export-BackupReport (BCK-069)' {
    BeforeEach {
        Mock -ModuleName WbaToolkit.Backup Test-VssHealth {
            [pscustomobject]@{ Healthy = $true; Checks = @([pscustomobject]@{ Name = 'Servico VSS'; Status = 'OK'; Detail = 'Running' }) }
        }
        Mock -ModuleName WbaToolkit.Backup Get-RestorePointInfo {
            [pscustomobject]@{ SequenceNumber = 4; Description = 'RP quatro'; CreationTime = (Get-Date '2026-11-01'); RestorePointType = 0 }
        }
        Mock -ModuleName WbaToolkit.Backup Get-BackupHistory {
            [pscustomobject]@{ BackupPath = 'C:\bk\s1'; CreatedAt = (Get-Date '2026-11-02'); AllSuccess = $false; SourceCount = 1 }
        }
        Mock -ModuleName WbaToolkit.Backup Get-BackupConfiguration { [pscustomobject]@{ UserBackup = [pscustomobject]@{ RetentionDays = 90 } } }
        $script:out = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:out -Force | Out-Null
    }

    It 'JSON contem saude, pontos de restauracao, historico e configuracao' {
        $arquivo = Join-Path $script:out 'r.json'

        $saida = Export-BackupReport -Format JSON -OutputPath $arquivo

        @($saida)[-1] | Should -Be $arquivo
        $j = Get-Content -Path $arquivo -Raw | ConvertFrom-Json
        $j.Health.Healthy | Should -BeTrue
        $j.RestorePoints[0].SequenceNumber | Should -Be 4
        $j.BackupHistory[0].BackupPath | Should -Be 'C:\bk\s1'
        $j.Configuration.UserBackup.RetentionDays | Should -Be 90
    }

    It 'TXT lista checks, pontos e historico com status' {
        $arquivo = Join-Path $script:out 'r.txt'

        Export-BackupReport -Format TXT -OutputPath $arquivo | Out-Null

        $txt = Get-Content -Path $arquivo -Raw
        $txt | Should -Match '\[OK\] Servico VSS: Running'
        $txt | Should -Match '#4 - RP quatro'
        $txt | Should -Match '\[FALHA\] .* - C:\\bk\\s1'
    }

    It 'HTML e gravado em UTF-8 com BOM e traz as tabelas' {
        $arquivo = Join-Path $script:out 'r.html'

        Export-BackupReport -Format HTML -OutputPath $arquivo | Out-Null

        $bytes = [System.IO.File]::ReadAllBytes($arquivo)
        $bytes[0..2] -join ',' | Should -Be '239,187,191'
        $html = [System.IO.File]::ReadAllText($arquivo)
        $html | Should -Match '<h2>Restore Points \(1\)</h2>'
        $html | Should -Match '<td>RP quatro</td>'
    }
}
