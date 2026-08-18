#requires -version 5.1

Describe 'Backup-DropboxItem' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $moduleRoot = Join-Path $repoRoot 'modules'
        
        # Adicionar ao PSModulePath se necessário
        if ($env:PSModulePath -notlike "*$moduleRoot*") {
            $env:PSModulePath = "$moduleRoot;$env:PSModulePath"
        }
        
        # Importar módulos na ordem correta
        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Maintenance\WbaToolkit.Maintenance.psd1') -Force
    }

    Context 'Arquivo existente' {
        It 'Deve criar backup com sucesso' {
            # Arrange
            $testDir = Join-Path $TestDrive 'backup-test'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $sourceFile = Join-Path $testDir 'arquivo.txt'
            Set-Content -LiteralPath $sourceFile -Value 'conteudo teste'
            $backupDir = Join-Path $testDir 'backups'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

            # Act
            $resultado = Backup-DropboxItem -Path $sourceFile -BackupDir $backupDir

            # Assert
            $resultado | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $backupDir 'arquivo.txt.backup') | Should -BeTrue
        }

        It 'Deve retornar true quando backup é criado' {
            # Arrange
            $testDir = Join-Path $TestDrive 'backup-test-2'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $sourceFile = Join-Path $testDir 'arquivo2.txt'
            Set-Content -LiteralPath $sourceFile -Value 'conteudo teste 2'
            $backupDir = Join-Path $testDir 'backups'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

            # Act
            $resultado = Backup-DropboxItem -Path $sourceFile -BackupDir $backupDir

            # Assert
            $resultado | Should -BeTrue
        }
    }

    Context 'Arquivo inexistente' {
        It 'Deve retornar false quando arquivo não existe' {
            # Arrange
            $testDir = Join-Path $TestDrive 'backup-test-3'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $sourceFile = Join-Path $testDir 'nao-existe.txt'
            $backupDir = Join-Path $testDir 'backups'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

            # Act
            $resultado = Backup-DropboxItem -Path $sourceFile -BackupDir $backupDir

            # Assert
            $resultado | Should -BeFalse
        }
    }

    Context 'Diretório de backup inválido' {
        It 'Deve retornar false quando diretório de backup não existe' {
            # Arrange
            $testDir = Join-Path $TestDrive 'backup-test-4'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $sourceFile = Join-Path $testDir 'arquivo4.txt'
            Set-Content -LiteralPath $sourceFile -Value 'conteudo teste 4'
            $backupDir = Join-Path $testDir 'backups-inexistentes'

            # Act
            $resultado = Backup-DropboxItem -Path $sourceFile -BackupDir $backupDir

            # Assert
            $resultado | Should -BeFalse
        }
    }
}

Describe 'Get-SafeFileName' {
    Context 'Caracteres inválidos' {
        It 'Deve remover caracteres inválidos do nome' {
            # Arrange
            $nome = 'arquivo<inválido>.txt'

            # Act
            $resultado = Get-SafeFileName -Name $nome

            # Assert
            $resultado | Should -Be 'arquivoinválido.txt'
        }

        It 'Deve remover todos os caracteres inválidos' {
            # Arrange
            $nome = 'arquivo:"|?*.txt'

            # Act
            $resultado = Get-SafeFileName -Name $nome

            # Assert
            $resultado | Should -Be 'arquivo.txt'
        }

        It 'Deve manter extensão original' {
            # Arrange
            $nome = 'documento<>.pdf'

            # Act
            $resultado = Get-SafeFileName -Name $nome

            # Assert
            $resultado | Should -Be 'documento.pdf'
        }
    }

    Context 'Nome muito longo' {
        It 'Deve truncar nomes longos com hash' {
            # Arrange
            $nome = 'a' * 300

            # Act
            $resultado = Get-SafeFileName -Name $nome

            # Assert
            $resultado.Length | Should -BeLessOrEqual 259
            $resultado | Should -Match '-[a-f0-9]{8}$'
        }

        It 'Deve respeitar MaxLength personalizado' {
            # Arrange
            $nome = 'a' * 100

            # Act
            $resultado = Get-SafeFileName -Name $nome -MaxLength 50

            # Assert
            $resultado.Length | Should -BeLessOrEqual 50
        }
    }

    Context 'Nome vazio ou apenas espaços' {
        It 'Deve lançar erro para string vazia' {
            # Act & Assert
            { Get-SafeFileName -Name '' } | Should -Throw
        }

        It 'Deve retornar nome padrão para apenas espaços' {
            # Act
            $resultado = Get-SafeFileName -Name '   '

            # Assert
            $resultado | Should -Be 'arquivo_sem_nome'
        }
    }

    Context 'Nome válido' {
        It 'Deve retornar nome sem alteração quando válido' {
            # Arrange
            $nome = 'arquivo_valido.txt'

            # Act
            $resultado = Get-SafeFileName -Name $nome

            # Assert
            $resultado | Should -Be $nome
        }

        It 'Deve remover espaços no final' {
            # Arrange
            $nome = 'arquivo_com_espaco   '

            # Act
            $resultado = Get-SafeFileName -Name $nome

            # Assert
            $resultado | Should -Be 'arquivo_com_espaco'
        }
    }
}

Describe 'New-DropboxPropostaHtmlReport' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $moduleRoot = Join-Path $repoRoot 'modules'
        
        # Adicionar ao PSModulePath se necessário
        if ($env:PSModulePath -notlike "*$moduleRoot*") {
            $env:PSModulePath = "$moduleRoot;$env:PSModulePath"
        }
        
        # Importar módulos na ordem correta
        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Maintenance\WbaToolkit.Maintenance.psd1') -Force
        
        # Dot-sourcing Private functions for direct access
        $privatePath = Join-Path $moduleRoot 'WbaToolkit.Maintenance\Private'
        Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
    }

    Context 'Geração de HTML' {
        It 'Deve gerar HTML válido com propostas' {
            # Arrange
            $propostas = @(
                [pscustomobject]@{
                    id = 1
                    selecionado = $true
                    caminho_original = 'C:\Dropbox\arquivo<inválido>.txt'
                    caminho_proposto = 'C:\Dropbox\arquivoinv_lido.txt'
                    tipo_correcao = 'Renomeacao'
                    motivo = 'Caracteres inválidos'
                },
                [pscustomobject]@{
                    id = 2
                    selecionado = $false
                    caminho_original = 'C:\Dropbox\documento.txt'
                    caminho_proposto = 'C:\Dropbox\documento.txt'
                    tipo_correcao = 'Nenhuma'
                    motivo = ''
                }
            )

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 2 -Selecionadas 1 -Propostas $propostas

            # Assert
            $html | Should -Not -BeNullOrEmpty
            $html | Should -Match 'Propostas de Normalização Dropbox'
            $html | Should -Match 'arquivoinv_lido.txt'
            $html | Should -Match 'documento.txt'
        }

        It 'Deve incluir filtro de busca JavaScript' {
            # Arrange
            $propostas = @([pscustomobject]@{
                id = 1
                selecionado = $true
                caminho_original = 'C:\Dropbox\teste.txt'
                caminho_proposto = 'C:\Dropbox\teste.txt'
                tipo_correcao = 'Nenhuma'
                motivo = ''
            })

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 1 -Selecionadas 1 -Propostas $propostas

            # Assert
            $html | Should -Match 'filterTable'
            $html | Should -Match 'function filterTable'
        }
    }
}

Describe 'New-DropboxResultadoHtmlReport' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $moduleRoot = Join-Path $repoRoot 'modules'
        
        # Adicionar ao PSModulePath se necessário
        if ($env:PSModulePath -notlike "*$moduleRoot*") {
            $env:PSModulePath = "$moduleRoot;$env:PSModulePath"
        }
        
        # Importar módulos na ordem correta
        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Maintenance\WbaToolkit.Maintenance.psd1') -Force
        
        # Dot-sourcing Private functions for direct access
        $privatePath = Join-Path $moduleRoot 'WbaToolkit.Maintenance\Private'
        Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
    }

    Context 'Geração de HTML' {
        It 'Deve gerar HTML válido com resultados' {
            # Arrange
            $resultados = @(
                [pscustomobject]@{
                    id = 1
                    de = 'C:\Dropbox\arquivo<inválido>.txt'
                    para = 'C:\Dropbox\arquivoinv_lido.txt'
                    status = 'Sucesso'
                    backup = 'C:\backups\arquivo<inválido>.txt.backup'
                    erro = ''
                    timestamp = '2026-08-18T00:10:12Z'
                },
                [pscustomobject]@{
                    id = 2
                    de = 'C:\Dropbox\documento.txt'
                    para = 'C:\Dropbox\documento.txt'
                    status = 'Erro'
                    backup = ''
                    erro = 'Arquivo não encontrado'
                    timestamp = '2026-08-18T00:10:13Z'
                }
            )

            # Act
            $html = New-DropboxResultadoHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalAplicadas 2 -Sucesso 1 -Falha 1 -Resultados $resultados

            # Assert
            $html | Should -Not -BeNullOrEmpty
            $html | Should -Match 'Resultado da Normalização Dropbox'
            $html | Should -Match 'arquivoinv_lido.txt'
            $html | Should -Match 'documento.txt'
        }

        It 'Deve incluir badges de status' {
            # Arrange
            $resultados = @([pscustomobject]@{
                id = 1
                de = 'C:\Dropbox\teste.txt'
                para = 'C:\Dropbox\teste.txt'
                status = 'Sucesso'
                backup = ''
                erro = ''
                timestamp = '2026-08-18T00:10:12Z'
            })

            # Act
            $html = New-DropboxResultadoHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalAplicadas 1 -Sucesso 1 -Falha 0 -Resultados $resultados

            # Assert
            $html | Should -Match 'badge-green'
            $html | Should -Match '✓ Sucesso'
        }
    }
}

Describe 'WbaToolkit.Maintenance - Normalização Dropbox' {
    Context 'Importação' {
        It 'Deve carregar módulo sem erro' {
            $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $modulePath = Join-Path (Join-Path $repoRoot 'modules') 'WbaToolkit.Maintenance\WbaToolkit.Maintenance.psd1'
            { Import-Module $modulePath -Force } | Should -Not -Throw
        }

        It 'Deve exportar novas funções' {
            # Act
            $mod = Get-Module WbaToolkit.Maintenance

            # Assert
            $mod.ExportedFunctions.Keys | Should -Contain 'Backup-DropboxItem'
            $mod.ExportedFunctions.Keys | Should -Contain 'Get-SafeFileName'
        }
    }
}
