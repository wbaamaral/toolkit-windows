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
        It 'Deve gerar HTML válido com o editor de diretórios (De/Para)' {
            # Arrange -- a unidade de correcao e o diretorio, nao o arquivo
            # (a renomeacao acontece na pasta), entao o relatorio nao tem mais
            # tabela por arquivo; -Diretorios e quem popula o conteudo real.
            $propostas = @([pscustomobject]@{
                id = 1; selecionado = $true
                caminho_original = 'C:\Dropbox\PastaComNomeGrande\arquivo.txt'
            })
            $diretorios = @(
                [pscustomobject]@{
                    id = 1
                    diretorio = 'C:\Dropbox\PastaComNomeGrande'
                    nome_original = 'PastaComNomeGrande'
                    nome_proposto = 'PastaCurta'
                    caminho_original = 'C:\Dropbox\PastaComNomeGrande'
                    caminho_proposto = 'C:\Dropbox\PastaCurta'
                    total_arquivos = 1
                    maior_sufixo = 12
                    problema_pred = 'Caminho > 260'
                    selecionado = $true
                    cadeia = @([pscustomobject]@{ nivel = 1; caminho_original = 'C:\Dropbox\PastaComNomeGrande'; nome_proposto = 'PastaCurta' })
                }
            )

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 1 -Selecionadas 1 -Propostas $propostas -Diretorios $diretorios

            # Assert
            $html | Should -Not -BeNullOrEmpty
            $html | Should -Match 'Propostas de Normalização Dropbox'
            $html | Should -Match 'PastaComNomeGrande'
            $html | Should -Match 'PastaCurta'
        }

        It 'Mostra De/Para empilhado com zebra e cabecalho fixo' {
            # Arrange
            $propostas = @([pscustomobject]@{ id = 1; selecionado = $true; caminho_original = 'C:\Dropbox\Teste\a.txt' })
            $diretorios = @(
                [pscustomobject]@{
                    id = 1; diretorio = 'C:\Dropbox\Teste'; nome_original = 'Teste'; nome_proposto = 'Teste'
                    caminho_original = 'C:\Dropbox\Teste'; caminho_proposto = 'C:\Dropbox\Teste'
                    total_arquivos = 1; maior_sufixo = 10; problema_pred = 'Caminho > 260'; selecionado = $true
                    cadeia = @([pscustomobject]@{ nivel = 1; caminho_original = 'C:\Dropbox\Teste'; nome_proposto = 'Teste' })
                }
            )

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 1 -Selecionadas 1 -Propostas $propostas -Diretorios $diretorios

            # Assert
            $html | Should -Match 'depara-rotulo-de'
            $html | Should -Match 'depara-rotulo-para'
            $html | Should -Match 'nth-child\(even\)'
            $html | Should -Match 'position:sticky'
        }

        It 'Deve incluir filtro de busca do editor de diretorios' {
            # Arrange
            $propostas = @([pscustomobject]@{ id = 1; selecionado = $true; caminho_original = 'C:\Dropbox\Teste\a.txt' })
            $diretorios = @(
                [pscustomobject]@{
                    id = 1; diretorio = 'C:\Dropbox\Teste'; nome_original = 'Teste'; nome_proposto = 'Teste'
                    caminho_original = 'C:\Dropbox\Teste'; caminho_proposto = 'C:\Dropbox\Teste'
                    total_arquivos = 1; maior_sufixo = 10; problema_pred = 'Caminho > 260'; selecionado = $true
                    cadeia = @([pscustomobject]@{ nivel = 1; caminho_original = 'C:\Dropbox\Teste'; nome_proposto = 'Teste' })
                }
            )

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 1 -Selecionadas 1 -Propostas $propostas -Diretorios $diretorios

            # Assert
            $html | Should -Match 'filterDiretorios'
            $html | Should -Match 'function filterDiretorios'
        }
    }

    Context 'Editor interativo de diretorios' {
        It 'Nao inclui a secao do editor quando -Diretorios e omitido (compatibilidade)' {
            # Arrange
            $propostas = @([pscustomobject]@{
                id = 1; selecionado = $true
                caminho_original = 'C:\Dropbox\teste.txt'; caminho_proposto = 'C:\Dropbox\teste.txt'
                tipo_correcao = 'Nenhuma'; motivo = ''
            })

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 1 -Selecionadas 1 -Propostas $propostas

            # Assert
            $html | Should -Not -Match 'baixarJsonCorrigido'
        }

        It 'Inclui checkbox, campo editavel, calculo de comprimento e botao de download quando -Diretorios e informado' {
            # Arrange
            $propostas = @([pscustomobject]@{
                id = 1; selecionado = $true
                caminho_original = 'C:\Dropbox\Pasta\arquivo.txt'; caminho_proposto = 'C:\Dropbox\Pasta\arquivo.txt'
                tipo_correcao = 'Renomeacao'; motivo = ''
            })
            $diretorios = @(
                [pscustomobject]@{
                    id = 1
                    diretorio = 'C:\Dropbox\PastaComNomeGrande'
                    nome_original = 'PastaComNomeGrande'
                    nome_proposto = 'PastaComNomeGrande'
                    caminho_original = 'C:\Dropbox\PastaComNomeGrande'
                    caminho_proposto = 'C:\Dropbox\PastaComNomeGrande'
                    total_arquivos = 3
                    maior_sufixo = 12
                    problema_pred = 'Caminho > 260'
                    selecionado = $true
                    cadeia = @([pscustomobject]@{ nivel = 1; caminho_original = 'C:\Dropbox\PastaComNomeGrande'; nome_proposto = 'PastaComNomeGrande' })
                }
            )
            $metadata = [pscustomobject]@{ diagnostico_origem = 'C:\diagnostico.json' }

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 1 -Selecionadas 1 -Propostas $propostas `
                -Diretorios $diretorios -MetadataOriginal $metadata -LimiteCaminho 260

            # Assert
            $html | Should -Match 'Editor de Diretórios'
            $html | Should -Match 'type="checkbox"'
            $html | Should -Match 'class="edit-nome"'
            $html | Should -Match 'function calcularComprimento'
            $html | Should -Match 'function atualizarNome'
            $html | Should -Match 'function baixarJsonCorrigido'
            $html | Should -Match 'diretoriosData'
            $html | Should -Match 'LIMITE_CAMINHO = 260'
        }

        It 'Repassa a cadeia de niveis para o JSON embutido no editor' {
            # Arrange
            $propostas = @([pscustomobject]@{
                id = 1; selecionado = $true
                caminho_original = 'C:\Dropbox\a\b\c'; caminho_proposto = 'C:\Dropbox\a\b\c'
                tipo_correcao = 'Renomeacao'; motivo = ''
            })
            $diretorios = @(
                [pscustomobject]@{
                    id = 1
                    diretorio = 'C:\Dropbox\a\b\c'
                    nome_original = 'c'
                    nome_proposto = 'c'
                    caminho_original = 'C:\Dropbox\a\b\c'
                    caminho_proposto = 'C:\Dropbox\aCurto\b\c'
                    total_arquivos = 1
                    maior_sufixo = 5
                    problema_pred = 'Caminho > 260'
                    selecionado = $true
                    cadeia = @(
                        [pscustomobject]@{ nivel = 1; caminho_original = 'C:\Dropbox\a'; nome_proposto = 'aCurto' }
                        [pscustomobject]@{ nivel = 2; caminho_original = 'C:\Dropbox\a\b\c'; nome_proposto = 'c' }
                    )
                }
            )

            # Act
            $html = New-DropboxPropostaHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalPropostas 1 -Selecionadas 1 -Propostas $propostas -Diretorios $diretorios

            # Assert
            $html | Should -Match 'cadeia: 2 niveis'
            $html | Should -Match 'aCurto'
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

        It 'Aceita o esquema atual (diretorio_origem/diretorio_destino/nome_novo)' {
            # Arrange
            $resultados = @([pscustomobject]@{
                id = 1
                diretorio_origem = 'C:\Dropbox\PastaAntiga'
                diretorio_destino = 'C:\Dropbox\PastaNova'
                nome_original = 'PastaAntiga'
                nome_novo = 'PastaNova'
                status = 'Sucesso'
                erro = ''
                timestamp = '2026-08-18T00:10:12Z'
            })

            # Act
            $html = New-DropboxResultadoHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalAplicadas 1 -Sucesso 1 -Falha 0 -Resultados $resultados

            # Assert
            $html | Should -Match 'PastaAntiga'
            $html | Should -Match 'PastaNova'
        }

        It 'Exibe os niveis da cadeia quando o resultado tem 2 ou mais niveis' {
            # Arrange
            $resultados = @([pscustomobject]@{
                id = 1
                diretorio_origem = 'C:\Dropbox\PastaGrandeAncestral\Filho'
                diretorio_destino = 'C:\Dropbox\PastaCurta\Filho'
                nome_original = 'PastaGrandeAncestral'
                nome_novo = 'Filho'
                status = 'Sucesso'
                erro = ''
                timestamp = '2026-08-18T00:10:12Z'
                cadeia = @(
                    [pscustomobject]@{ nivel = 1; caminho_original = 'C:\Dropbox\PastaGrandeAncestral'; nome_proposto = 'PastaCurta'; status = 'Sucesso'; erro = '' }
                    [pscustomobject]@{ nivel = 2; caminho_original = 'C:\Dropbox\PastaGrandeAncestral\Filho'; nome_proposto = 'Filho'; status = 'Sucesso'; erro = '' }
                )
            })

            # Act
            $html = New-DropboxResultadoHtmlReport -DropboxPath 'C:\Dropbox' `
                -TotalAplicadas 1 -Sucesso 1 -Falha 0 -Resultados $resultados

            # Assert
            $html | Should -Match 'cadeia-detalhe'
            $html | Should -Match 'Nível 1'
            $html | Should -Match 'Nível 2'
            $html | Should -Match 'PastaCurta'
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

Describe 'Get-DiretoriosProblematicos' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $moduleRoot = Join-Path $repoRoot 'modules'

        if ($env:PSModulePath -notlike "*$moduleRoot*") {
            $env:PSModulePath = "$moduleRoot;$env:PSModulePath"
        }

        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
        Import-Module (Join-Path $moduleRoot 'WbaToolkit.Maintenance\WbaToolkit.Maintenance.psd1') -Force

        # Get-SafeFileName e publica (ja disponivel via Import-Module); a funcao sob
        # teste e privada, entao e dot-sourceada diretamente (mesmo padrao ja usado
        # pelos testes de New-DropboxPropostaHtmlReport/New-DropboxResultadoHtmlReport).
        $privatePath = Join-Path $moduleRoot 'WbaToolkit.Maintenance\Private'
        . (Join-Path $privatePath 'Get-DiretoriosProblematicos.ps1')
    }

    Context 'Diretorio ja cabe no limite (0 niveis de encadeamento)' {
        It 'Nao propoe encadeamento e marca como ja_valido' {
            # Arrange
            $raiz = '/tmp/wba-pester-raiz-0niveis'
            $dir = Join-Path $raiz 'PastaSimplesValida'
            $arquivo = Join-Path $dir 'arquivo.txt'
            $arquivos = @([pscustomobject]@{ Caminho = $arquivo; Nome = 'arquivo.txt' })

            # Act
            $resultado = Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raiz

            # Assert
            # @() forca o wrap em array antes do .Count: em PowerShell 5.1 real
            # (diferente do pwsh 7+), quando a funcao retorna exatamente 1 objeto
            # via pipeline, PowerShell nao o envolve em array, e .Count num
            # pscustomobject unico retorna $null em vez de lancar erro (mesma
            # classe de bug ja documentada no BCK-031).
            @($resultado).Count | Should -Be 1
            $resultado[0].resolvido | Should -BeTrue
            $resultado[0].atingiu_raiz | Should -BeFalse
            $resultado[0].ja_valido | Should -BeTrue
            @($resultado[0].cadeia).Count | Should -Be 1
        }
    }

    Context 'Encadeamento precisa subir exatamente 1 nivel' {
        It 'Encurta o diretorio ancestral quando so o nivel mais profundo nao basta' {
            # Arrange: nome do diretorio mais profundo ja e valido (Get-SafeFileName
            # nao o altera), mas o caminho completo so cabe apos encurtar o ancestral.
            $raiz = '/tmp/wba-pester-raiz-1nivel'
            $nivelAncestral = 'P' * 200
            $nivelProfundo = 'Q' * 30
            $dirProfundo = Join-Path $raiz (Join-Path $nivelAncestral $nivelProfundo)
            $nomeArquivo = ('r' * 20) + '.txt'
            $caminhoArquivo = Join-Path $dirProfundo $nomeArquivo
            $arquivos = @([pscustomobject]@{ Caminho = $caminhoArquivo; Nome = $nomeArquivo })

            # Precondicao: o caminho original deve de fato ultrapassar o limite padrao
            $caminhoArquivo.Length | Should -BeGreaterThan 260

            # Act
            $resultado = Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raiz

            # Assert
            $resultado[0].resolvido | Should -BeTrue
            $resultado[0].atingiu_raiz | Should -BeFalse
            @($resultado[0].cadeia).Count | Should -Be 2

            $cadeiaOrdenada = @($resultado[0].cadeia | Sort-Object nivel)
            $cadeiaOrdenada[0].nome_proposto.Length | Should -BeLessThan $nivelAncestral.Length
            $cadeiaOrdenada[1].nome_proposto | Should -Be $nivelProfundo

            $comprimentoFinal = $resultado[0].caminho_proposto.Length + $resultado[0].maior_sufixo
            $comprimentoFinal | Should -BeLessOrEqual 250
        }
    }

    Context 'Encadeamento precisa subir 2 ou mais niveis' {
        It 'Encurta mais de um ancestral quando um so nao e suficiente' {
            # Arrange: o ancestral imediato (nivel 2) e curto -- encurta-lo sozinho
            # nao resolve -- entao o encadeamento precisa subir mais um nivel
            # (nivel 1, bem mais longo) para caber no limite.
            $raiz = '/tmp/wba-pester-raiz-2niveis'
            $nivel1 = 'L' + ('x' * 300)
            $nivel2 = 'M' * 15
            $nivelProfundo = 'N' * 20
            $dirProfundo = Join-Path $raiz (Join-Path $nivel1 (Join-Path $nivel2 $nivelProfundo))
            $nomeArquivo = ('o' * 20) + '.pdf'
            $caminhoArquivo = Join-Path $dirProfundo $nomeArquivo
            $arquivos = @([pscustomobject]@{ Caminho = $caminhoArquivo; Nome = $nomeArquivo })

            # Act
            $resultado = Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raiz

            # Assert
            $resultado[0].resolvido | Should -BeTrue
            $resultado[0].atingiu_raiz | Should -BeFalse
            @($resultado[0].cadeia).Count | Should -Be 3

            $cadeiaOrdenada = @($resultado[0].cadeia | Sort-Object nivel)
            $cadeiaOrdenada[0].nome_proposto.Length | Should -BeLessThan $nivel1.Length
            $cadeiaOrdenada[1].nome_proposto.Length | Should -BeLessThan $nivel2.Length
            $cadeiaOrdenada[2].nome_proposto | Should -Be $nivelProfundo

            $comprimentoFinal = $resultado[0].caminho_proposto.Length + $resultado[0].maior_sufixo
            $comprimentoFinal | Should -BeLessOrEqual 250
        }
    }

    Context 'Ancestral curto demais para o hash de Get-SafeFileName encurtar' {
        It 'Mantem o nome original do ancestral em vez de troca-lo por algo do mesmo tamanho ou maior' {
            # Arrange: achado real na validacao contra o Dropbox de producao (BCK-061)
            # -- um ancestral curto (aqui 8 chars) fica no meio da cadeia. O hash de
            # Get-SafeFileName tem piso de ~10 chars (1 char + hifen + hash de 8),
            # entao "encurtar" um nome de 8 chars produziria algo MAIOR (10 chars),
            # nunca menor. O ancestral genuinamente longo (nivel1) e quem deve
            # resolver o excesso.
            $raiz = '/tmp/wba-pester-raiz-ancestral-curto'
            $nivel1 = 'L' + ('x' * 300)
            $nivel2Curto = 'M' * 8
            $nivelProfundo = 'N' * 20
            $dirProfundo = Join-Path $raiz (Join-Path $nivel1 (Join-Path $nivel2Curto $nivelProfundo))
            $nomeArquivo = ('o' * 20) + '.pdf'
            $caminhoArquivo = Join-Path $dirProfundo $nomeArquivo
            $arquivos = @([pscustomobject]@{ Caminho = $caminhoArquivo; Nome = $nomeArquivo })

            # Act
            $resultado = Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raiz

            # Assert
            $resultado[0].resolvido | Should -BeTrue

            $cadeiaOrdenada = @($resultado[0].cadeia | Sort-Object nivel)
            $entradaNivel2 = $cadeiaOrdenada | Where-Object { (Split-Path -Leaf $_.caminho_original) -eq $nivel2Curto }
            $entradaNivel2 | Should -Not -BeNullOrEmpty
            $entradaNivel2.nome_proposto | Should -Be $nivel2Curto

            $entradaNivel1 = $cadeiaOrdenada | Where-Object { (Split-Path -Leaf $_.caminho_original) -eq $nivel1 }
            $entradaNivel1 | Should -Not -BeNullOrEmpty
            $entradaNivel1.nome_proposto.Length | Should -BeLessThan $nivel1.Length

            $comprimentoFinal = $resultado[0].caminho_proposto.Length + $resultado[0].maior_sufixo
            $comprimentoFinal | Should -BeLessOrEqual 250
        }
    }

    Context 'Encadeamento atinge CaminhoRaiz sem conseguir caber' {
        It 'Reporta nao resolvido automaticamente em vez de falhar silenciosamente' {
            # Arrange: nome de diretorio gigantesco cujo unico ancestral disponivel
            # e a propria raiz protegida (nunca renomeada).
            $raizCurta = '/tmp/wba-pester-rc'
            $nomeGigante = 'X' * 300
            $dirProfundo = Join-Path $raizCurta $nomeGigante
            $arquivos = @([pscustomobject]@{ Caminho = (Join-Path $dirProfundo 'f.txt'); Nome = 'f.txt' })

            # Act
            $resultado = Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raizCurta

            # Assert
            $resultado[0].resolvido | Should -BeFalse
            $resultado[0].atingiu_raiz | Should -BeTrue
            { Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raizCurta } | Should -Not -Throw
        }
    }

    Context 'Parametros de limite configuraveis' {
        It 'Respeita -LimiteCaminho e -MargemSeguranca customizados' {
            # Arrange: caminho que cabe no padrao (260/10) mas nao cabe num limite
            # bem mais restritivo.
            $raiz = '/tmp/wba-pester-raiz-custom'
            $dir = Join-Path $raiz ('D' * 40)
            $arquivo = Join-Path $dir (('e' * 20) + '.txt')
            $arquivos = @([pscustomobject]@{ Caminho = $arquivo; Nome = (('e' * 20) + '.txt') })

            # Act
            $resultadoPadrao = Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raiz
            $resultadoRestrito = Get-DiretoriosProblematicos -Arquivos $arquivos -CaminhoRaiz $raiz -LimiteCaminho 50 -MargemSeguranca 5

            # Assert
            $resultadoPadrao[0].resolvido | Should -BeTrue
            @($resultadoPadrao[0].cadeia).Count | Should -Be 1
            $resultadoRestrito[0].atingiu_raiz | Should -BeTrue
            $resultadoRestrito[0].resolvido | Should -BeFalse
        }
    }
}

Describe 'Invoke-DropboxCadeiaRename' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $moduleRoot = Join-Path $repoRoot 'modules'
        $privatePath = Join-Path $moduleRoot 'WbaToolkit.Maintenance\Private'
        . (Join-Path $privatePath 'Invoke-DropboxCadeiaRename.ps1')
    }

    Context 'Cadeia de 2 niveis aplicada com sucesso' {
        It 'Renomeia do nivel mais raso para o mais profundo e retorna o caminho final correto' {
            # Arrange
            $raiz = Join-Path $TestDrive 'raiz-cadeia-2'
            $ancestralOriginal = Join-Path $raiz 'AncestralOriginalNomeGrande'
            $profundoOriginal = Join-Path $ancestralOriginal 'FilhoOriginal'
            New-Item -ItemType Directory -Path $profundoOriginal -Force | Out-Null

            $cadeia = @(
                [pscustomobject]@{ nivel = 1; caminho_original = $ancestralOriginal; nome_proposto = 'AncestralCurto' }
                [pscustomobject]@{ nivel = 2; caminho_original = $profundoOriginal; nome_proposto = 'FilhoCurto' }
            )

            # Act
            $resultado = Invoke-DropboxCadeiaRename -Cadeia $cadeia

            # Assert
            $resultado.sucesso | Should -BeTrue
            $caminhoEsperado = Join-Path (Join-Path $raiz 'AncestralCurto') 'FilhoCurto'
            $resultado.caminho_final | Should -Be $caminhoEsperado
            Test-Path -LiteralPath $resultado.caminho_final -PathType Container | Should -BeTrue

            # O ancestral original nao deve mais existir (foi renomeado)
            Test-Path -LiteralPath $ancestralOriginal | Should -BeFalse

            # Regressao de ordem: se o filho tivesse sido endereçado pelo caminho
            # original (ancestral antigo) em vez do caminho ja atualizado, este
            # hibrido nao deveria existir -- prova de que o ancestral foi
            # renomeado ANTES do filho ser endereçado.
            Test-Path -LiteralPath (Join-Path $ancestralOriginal 'FilhoCurto') | Should -BeFalse
        }
    }

    Context 'Falha em um nivel intermediario' {
        It 'Marca os niveis restantes como NaoExecutado e nao falha silenciosamente' {
            # Arrange: nivel 1 existe de fato; niveis 2 e 3 nunca foram criados no
            # disco, entao o nivel 2 falha com "Diretorio nao encontrado" apos o
            # nivel 1 ser renomeado com sucesso.
            $raizB = Join-Path $TestDrive 'raiz-cadeia-falha'
            $n1 = Join-Path $raizB 'Nivel1Original'
            $n2 = Join-Path $n1 'Nivel2Original'
            $n3 = Join-Path $n2 'Nivel3Original'
            New-Item -ItemType Directory -Path $n1 -Force | Out-Null

            $cadeia = @(
                [pscustomobject]@{ nivel = 1; caminho_original = $n1; nome_proposto = 'N1Novo' }
                [pscustomobject]@{ nivel = 2; caminho_original = $n2; nome_proposto = 'N2Novo' }
                [pscustomobject]@{ nivel = 3; caminho_original = $n3; nome_proposto = 'N3Novo' }
            )

            # Act
            $resultado = Invoke-DropboxCadeiaRename -Cadeia $cadeia

            # Assert
            $resultado.sucesso | Should -BeFalse
            $resultado.erro | Should -Not -BeNullOrEmpty

            $niveisOrdenados = @($resultado.niveis | Sort-Object nivel)
            $niveisOrdenados[0].status | Should -Be 'Sucesso'
            $niveisOrdenados[1].status | Should -Be 'Erro'
            $niveisOrdenados[2].status | Should -Be 'NaoExecutado'

            # O nivel 1 realmente foi renomeado no disco antes da falha do nivel 2
            Test-Path -LiteralPath (Join-Path $raizB 'N1Novo') -PathType Container | Should -BeTrue
        }
    }

    Context 'Cadeia de 1 nivel (compatibilidade com propostas de nivel unico)' {
        It 'Aplica normalmente quando a cadeia tem apenas o nivel mais profundo' {
            # Arrange
            $raiz = Join-Path $TestDrive 'raiz-cadeia-1'
            $dirOriginal = Join-Path $raiz 'PastaOriginal'
            New-Item -ItemType Directory -Path $dirOriginal -Force | Out-Null

            $cadeia = @([pscustomobject]@{ nivel = 1; caminho_original = $dirOriginal; nome_proposto = 'PastaNova' })

            # Act
            $resultado = Invoke-DropboxCadeiaRename -Cadeia $cadeia

            # Assert
            $resultado.sucesso | Should -BeTrue
            $resultado.caminho_final | Should -Be (Join-Path $raiz 'PastaNova')
            Test-Path -LiteralPath $resultado.caminho_final -PathType Container | Should -BeTrue
        }
    }
}
