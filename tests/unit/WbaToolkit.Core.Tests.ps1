# Projeto: wba-toolkit
# Autor: wbaamaral

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'

    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'WbaToolkit.Core' {
    Context 'Exportacao do modulo' {
        It 'Deve exportar Test-IsAdministrator' {
            (Get-Command Test-IsAdministrator -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Invoke-Safe' {
            (Get-Command Invoke-Safe -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Format-FileSize' {
            (Get-Command Format-FileSize -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-Ok' {
            (Get-Command Write-Ok -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-Fail' {
            (Get-Command Write-Fail -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-Warn' {
            (Get-Command Write-Warn -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-Info' {
            (Get-Command Write-Info -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-Title' {
            (Get-Command Write-Title -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-Section' {
            (Get-Command Write-Section -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-Step' {
            (Get-Command Write-Step -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Read-YesNo' {
            (Get-Command Read-YesNo -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Invoke-ExternalCommand' {
            (Get-Command Invoke-ExternalCommand -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar ConvertTo-HtmlSafe' {
            (Get-Command ConvertTo-HtmlSafe -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Export-ToolkitFunctionDocs' {
            (Get-Command Export-ToolkitFunctionDocs -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar funcoes de padronizacao de relatorios' {
            (Get-Command Get-ToolkitReportsRoot -ErrorAction Stop).CommandType | Should -Be 'Function'
            (Get-Command Set-ToolkitReportsRoot -ErrorAction Stop).CommandType | Should -Be 'Function'
            (Get-Command Initialize-ToolkitReportSession -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Read-UserInput' {
            (Get-Command Read-UserInput -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Get-Utf8BomEncoding' {
            (Get-Command Get-Utf8BomEncoding -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-TextFileUtf8' {
            (Get-Command Write-TextFileUtf8 -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Write-ScriptLog' {
            (Get-Command Write-ScriptLog -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Initialize-ScriptSession' {
            (Get-Command Initialize-ScriptSession -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Get-CimInstanceSafe' {
            (Get-Command Get-CimInstanceSafe -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'Deve exportar Get-ToolkitConfiguration' {
            (Get-Command Get-ToolkitConfiguration -ErrorAction Stop).CommandType | Should -Be 'Function'
        }
    }

    Context 'Formatacao de tamanho' {
        # Format-FileSize usa "{0:N1}"/"{0:N2}" (sensivel a cultura). O separador
        # decimal varia por cultura (pt-BR usa virgula) e isso e comportamento
        # esperado, nao defeito (ver spec/IMPLEMENTADO.md). Por isso o esperado e
        # calculado com a mesma cultura/formato, validando unidade, valor e precisao
        # sem fixar o separador decimal.
        It 'Deve formatar bytes pequenos em KB' {
            $esperado = '{0:N1} KB' -f (1536 / 1KB)
            Format-FileSize -Bytes 1536 | Should -Be $esperado
        }

        It 'Deve formatar gigabytes corretamente' {
            $esperado = '{0:N2} GB' -f ([long]2GB / 1GB)
            Format-FileSize -Bytes ([long]2GB) | Should -Be $esperado
        }
    }

    Context 'Execucao segura' {
        It 'Deve retornar verdadeiro quando o bloco executa com sucesso' {
            Invoke-Safe -Description 'Teste' -Command { return $true } | Should -BeTrue
        }

        It 'Deve retornar falso quando o bloco falha' {
            Invoke-Safe -Description 'Teste de falha' -Command { throw 'falha simulada' } | Should -BeFalse
        }
    }

    Context 'Comandos externos' {
        It 'Deve sinalizar comando inexistente' {
            $result = Invoke-ExternalCommand -FilePath 'comando-inexistente-do-wba' -ArgumentList @()
            $result.ExitCode | Should -Be 127
            $result.Output | Should -Match 'Comando não encontrado'
        }
    }

    Context 'Escape HTML' {
        It 'Deve escapar caracteres especiais' {
            ConvertTo-HtmlSafe -Value '<a>&b' | Should -Be '&lt;a&gt;&amp;b'
        }

        It 'Deve escapar aspas duplas' {
            ConvertTo-HtmlSafe -Value '"valor"' | Should -Be '&quot;valor&quot;'
        }

        It 'Deve retornar default quando valor e vazio' {
            ConvertTo-HtmlSafe -Value '' | Should -Be '<span class="muted">&mdash;</span>'
        }
    }

    Context 'Elevacao' {
        It 'Deve retornar valor booleano' {
            Test-IsAdministrator | Should -BeOfType [bool]
        }
    }

    Context 'Saida padronizada de relatorios' {
        It 'Deve usar caminho informado pelo usuario com prioridade' {
            $configPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-config-' + [guid]::NewGuid().ToString() + '.json')
            $userPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-reports-' + [guid]::NewGuid().ToString())

            Get-ToolkitReportsRoot -Path $userPath -ConfigPath $configPath | Should -Be $userPath
        }

        It 'Deve usar ReportsRoot persistente quando parametro nao for informado' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-config-' + [guid]::NewGuid().ToString())
            $configPath = Join-Path $tempDir 'config.json'
            $reportsRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-reports-' + [guid]::NewGuid().ToString())

            try {
                Set-ToolkitReportsRoot -Path $reportsRoot -ConfigPath $configPath | Out-Null
                Get-ToolkitReportsRoot -ConfigPath $configPath | Should -Be $reportsRoot
            }
            finally {
                if (Test-Path -LiteralPath $tempDir) {
                    Remove-Item -LiteralPath $tempDir -Recurse -Force
                }
            }
        }

        It 'Deve tratar ReportsRoot vazio como ausente e usar configuracao persistente' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-config-' + [guid]::NewGuid().ToString())
            $configPath = Join-Path $tempDir 'config.json'
            $reportsRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-reports-' + [guid]::NewGuid().ToString())

            try {
                Set-ToolkitReportsRoot -Path $reportsRoot -ConfigPath $configPath | Out-Null
                Get-ToolkitReportsRoot -Path '' -ConfigPath $configPath | Should -Be $reportsRoot
            }
            finally {
                if (Test-Path -LiteralPath $tempDir) {
                    Remove-Item -LiteralPath $tempDir -Recurse -Force
                }
            }
        }

        It 'Deve criar sessao usando ReportsRoot persistente quando ReportsRoot nao for informado' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-config-' + [guid]::NewGuid().ToString())
            $configPath = Join-Path $tempDir 'config.json'
            $reportsRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-reports-' + [guid]::NewGuid().ToString())

            try {
                Set-ToolkitReportsRoot -Path $reportsRoot -ConfigPath $configPath | Out-Null
                $session = Initialize-ToolkitReportSession -ModuleName 'Inventory' -ExecutionName '2026-06-10_110000' -ConfigPath $configPath
                $session.Path | Should -Be (Join-Path (Join-Path $reportsRoot 'Inventory') '2026-06-10_110000')
                Test-Path -LiteralPath $session.LogsPath | Should -BeTrue
                Test-Path -LiteralPath $session.BackupsPath | Should -BeTrue
            }
            finally {
                if (Test-Path -LiteralPath $reportsRoot) {
                    Remove-Item -LiteralPath $reportsRoot -Recurse -Force
                }
                if (Test-Path -LiteralPath $tempDir) {
                    Remove-Item -LiteralPath $tempDir -Recurse -Force
                }
            }
        }

        It 'Deve criar sessao com agrupamento por modulo e timestamp' {
            $reportsRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-reports-' + [guid]::NewGuid().ToString())

            try {
                $session = Initialize-ToolkitReportSession -ReportsRoot $reportsRoot -ModuleName 'HD100' -ExecutionName '2026-06-10_103000'
                $session.Path | Should -Be (Join-Path (Join-Path $reportsRoot 'HD100') '2026-06-10_103000')
                Test-Path -LiteralPath $session.LogsPath | Should -BeTrue
                Test-Path -LiteralPath $session.BackupsPath | Should -BeTrue
            }
            finally {
                if (Test-Path -LiteralPath $reportsRoot) {
                    Remove-Item -LiteralPath $reportsRoot -Recurse -Force
                }
            }
        }
    }

    Context 'Documentacao estatica' {
        It 'Deve gerar indice HTML local' {
            $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $outputPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-docs-' + [guid]::NewGuid().ToString())
            $modulePath = Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
            # ScriptPath explicito: elimina dependencia do CWD (default usa Get-Location).
            $scriptPaths = @(
                (Join-Path $repoRoot 'maintenance/Diagnostico-Reparo-HD100.ps1'),
                (Join-Path $repoRoot 'maintenance/limpeza-windows.ps1'),
                (Join-Path $repoRoot 'diagnostics/Diagnostico-Driver-Grafico.ps1')
            )

            $result = Export-ToolkitFunctionDocs -ModulePath $modulePath -OutputPath $outputPath -ScriptPath $scriptPaths -Force

            Test-Path -LiteralPath $result.Path | Should -BeTrue
            [System.IO.Path]::IsPathRooted($result.Path) | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputPath 'functions/Export-ToolkitFunctionDocs.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputPath 'functions/Get-StaticDocsMetadata.html') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $outputPath 'scripts/Diagnostico-Reparo-HD100.ps1.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputPath 'scripts/limpeza-windows.ps1.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputPath 'scripts/Diagnostico-Driver-Grafico.ps1.html') | Should -BeTrue
            $result.ScriptCount | Should -BeGreaterThan 0

            $content = Get-Content -LiteralPath $result.Path -Raw
            $content | Should -Match 'Manual de Funcoes'
            $content | Should -Match 'Export-ToolkitFunctionDocs'
            $content | Should -Match 'Indice de scripts'
            $content | Should -Match 'Diagnostico-Reparo-HD100.ps1'
            $content | Should -Match 'limpeza-windows.ps1'

            $functionContent = Get-Content -LiteralPath (Join-Path $outputPath 'functions/Export-ToolkitFunctionDocs.html') -Raw
            $functionContent | Should -Match 'Metadados do manual'
            $functionContent | Should -Match 'Documentacao'

            $scriptContent = Get-Content -LiteralPath (Join-Path $outputPath 'scripts/limpeza-windows.ps1.html') -Raw
            $scriptContent | Should -Match 'Limpeza segura'
            $scriptContent | Should -Match 'Como executar'
        }

        It 'Deve resolver caminho relativo de saida a partir da localizacao atual do PowerShell' {
            $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $modulePath = Join-Path $repoRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
            $relativeOutputPath = '.wba-docs-test-' + [guid]::NewGuid().ToString()

            Push-Location $repoRoot
            try {
                $result = Export-ToolkitFunctionDocs -ModulePath $modulePath -OutputPath $relativeOutputPath -Force

                [System.IO.Path]::IsPathRooted($result.Path) | Should -BeTrue
                $result.Path | Should -Match ([regex]::Escape($repoRoot))
                Test-Path -LiteralPath $result.Path | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $repoRoot (Join-Path $relativeOutputPath 'index.html')) | Should -BeTrue
            }
            finally {
                Pop-Location
                $cleanupPath = Join-Path $repoRoot $relativeOutputPath
                if (Test-Path -LiteralPath $cleanupPath) {
                    Remove-Item -LiteralPath $cleanupPath -Recurse -Force
                }
            }
        }
    }

    Context 'Entrada do operador' {
        BeforeEach {
            Mock Read-Host { return 'valor-digitado' }
        }

        It 'Read-UserInput deve retornar o valor digitado pelo operador' {
            $result = Read-UserInput -Question 'Pergunta'
            $result | Should -Be 'valor-digitado'
        }

        It 'Read-UserInput deve retornar DefaultValue quando operador pressiona ENTER sem digitar' {
            Mock Read-Host { return '' }
            $result = Read-UserInput -Question 'Pergunta' -DefaultValue 'padrao'
            $result | Should -Be 'padrao'
        }

        It 'Read-UserInput deve retornar valor digitado mesmo quando DefaultValue e informado' {
            Mock Read-Host { return 'digitado' }
            $result = Read-UserInput -Question 'Pergunta' -DefaultValue 'padrao'
            $result | Should -Be 'digitado'
        }
    }

    Context 'Encoding UTF-8 com BOM' {
        It 'Get-Utf8BomEncoding deve retornar System.Text.UTF8Encoding' {
            $enc = Get-Utf8BomEncoding
            $enc | Should -BeOfType [System.Text.UTF8Encoding]
        }

        It 'Get-Utf8BomEncoding deve retornar encoding com bytes de BOM 0xEF 0xBB 0xBF' {
            $preamble = Get-Utf8BomEncoding | ForEach-Object { $_.GetPreamble() }
            $preamble.Count | Should -Be 3
            $preamble[0] | Should -Be 0xEF
            $preamble[1] | Should -Be 0xBB
            $preamble[2] | Should -Be 0xBF
        }

        It 'Write-TextFileUtf8 deve criar arquivo com BOM' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-utf8-' + [guid]::NewGuid().ToString() + '.txt')
            try {
                Write-TextFileUtf8 -Path $path -Content 'conteudo de teste'
                Test-Path -LiteralPath $path | Should -BeTrue
                $bytes = [System.IO.File]::ReadAllBytes($path)
                $bytes[0] | Should -Be 0xEF
                $bytes[1] | Should -Be 0xBB
                $bytes[2] | Should -Be 0xBF
            }
            finally {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            }
        }

        It 'Write-TextFileUtf8 deve sobrescrever arquivo existente por padrao' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-utf8-' + [guid]::NewGuid().ToString() + '.txt')
            try {
                Write-TextFileUtf8 -Path $path -Content 'primeiro'
                Write-TextFileUtf8 -Path $path -Content 'segundo'
                $content = [System.IO.File]::ReadAllText($path, (Get-Utf8BomEncoding))
                $content | Should -Be 'segundo'
            }
            finally {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            }
        }

        It 'Write-TextFileUtf8 deve acrescentar conteudo em modo Append' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-utf8-' + [guid]::NewGuid().ToString() + '.txt')
            try {
                Write-TextFileUtf8 -Path $path -Content 'linha1'
                Write-TextFileUtf8 -Path $path -Content 'linha2' -Append
                $content = [System.IO.File]::ReadAllText($path, (Get-Utf8BomEncoding))
                $content | Should -Match 'linha1'
                $content | Should -Match 'linha2'
            }
            finally {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            }
        }
    }

    Context 'Log de script' {
        It 'Write-ScriptLog deve gravar entrada no arquivo de log com nivel e mensagem' {
            $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-log-' + [guid]::NewGuid().ToString() + '.log')
            try {
                Write-ScriptLog -Message 'mensagem de teste' -Level INFO -LogPath $logPath
                Test-Path -LiteralPath $logPath | Should -BeTrue
                $content = Get-Content -LiteralPath $logPath -Raw
                $content | Should -Match '\[INFO\]'
                $content | Should -Match 'mensagem de teste'
            }
            finally {
                if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
            }
        }

        It 'Write-ScriptLog deve incluir timestamp no formato yyyy-MM-dd HH:mm:ss' {
            $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-log-' + [guid]::NewGuid().ToString() + '.log')
            try {
                Write-ScriptLog -Message 'timestamp' -LogPath $logPath
                $content = Get-Content -LiteralPath $logPath -Raw
                $content | Should -Match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
            }
            finally {
                if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
            }
        }

        It 'Write-ScriptLog nao deve lancar excecao quando LogPath e omitido' {
            { Write-ScriptLog -Message 'sem arquivo' -Level INFO } | Should -Not -Throw
        }
    }

    Context 'Sessao de script' {
        It 'Initialize-ScriptSession deve retornar objeto com as propriedades esperadas' {
            $reportsRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-reports-' + [guid]::NewGuid().ToString())
            try {
                $session = Initialize-ScriptSession -ModuleName 'Teste' -BasePath $reportsRoot -ExecutionMode 'Diagnostico'
                $props = $session.PSObject.Properties.Name
                $props | Should -Contain 'StartedAt'
                $props | Should -Contain 'Mode'
                $props | Should -Contain 'ReportsRoot'
                $props | Should -Contain 'BasePath'
                $props | Should -Contain 'Path'
                $props | Should -Contain 'LogsPath'
                $props | Should -Contain 'BackupsPath'
                $session.Mode | Should -Be 'Diagnostico'
            }
            finally {
                if (Test-Path -LiteralPath $reportsRoot) { Remove-Item -LiteralPath $reportsRoot -Recurse -Force }
            }
        }

        It 'Initialize-ScriptSession deve ter StartedAt como DateTime' {
            $reportsRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-reports-' + [guid]::NewGuid().ToString())
            try {
                $session = Initialize-ScriptSession -ModuleName 'Teste' -BasePath $reportsRoot
                $session.StartedAt | Should -BeOfType [datetime]
            }
            finally {
                if (Test-Path -LiteralPath $reportsRoot) { Remove-Item -LiteralPath $reportsRoot -Recurse -Force }
            }
        }
    }

    Context 'Consulta CIM segura' {
        It 'Get-CimInstanceSafe deve retornar array vazio para classe invalida' {
            $result = @(Get-CimInstanceSafe -ClassName 'WBA_ClasseInexistente_99999')
            $result.Count | Should -Be 0
        }

        It 'Get-CimInstanceSafe deve retornar array para classe valida' {
            $result = @(Get-CimInstanceSafe -ClassName 'Win32_OperatingSystem')
            if ($result.Count -eq 0) {
                Set-ItResult -Skipped -Because 'CIM nao disponivel neste ambiente de teste'
                return
            }
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Configuracao do toolkit' {
        It 'Get-ToolkitConfiguration deve retornar PSCustomObject com ConfigPath quando arquivo nao existe' {
            $configPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-cfg-' + [guid]::NewGuid().ToString() + '.json')
            $result = Get-ToolkitConfiguration -ConfigPath $configPath
            $result | Should -BeOfType [psobject]
            $result.PSObject.Properties.Name | Should -Contain 'ConfigPath'
            $result.ConfigPath | Should -Be $configPath
        }

        It 'Get-ToolkitConfiguration deve ler propriedades de arquivo JSON existente' {
            $configPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wba-cfg-' + [guid]::NewGuid().ToString() + '.json')
            try {
                '{"ReportsRoot": "C:\\WBA\\Relatorios"}' | Set-Content -LiteralPath $configPath -Encoding UTF8
                $result = Get-ToolkitConfiguration -ConfigPath $configPath
                $result.ReportsRoot | Should -Be 'C:\WBA\Relatorios'
                $result.ConfigPath  | Should -Be $configPath
            }
            finally {
                if (Test-Path -LiteralPath $configPath) { Remove-Item -LiteralPath $configPath -Force }
            }
        }
    }

    Context 'Write-Step' {
        It 'Deve executar sem lancar excecao' {
            { Write-Step -Message 'Etapa de teste' -Percent 42 } | Should -Not -Throw
        }
        It 'Deve aceitar Percent 0' {
            { Write-Step 'Inicio' 0 } | Should -Not -Throw
        }
        It 'Deve aceitar Percent 100' {
            { Write-Step 'Fim' 100 } | Should -Not -Throw
        }
    }

    Context 'Export-ToolkitDocumentation' {
        BeforeAll {
            $repoRootLocal = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        }

        It 'e exportada pelo modulo' {
            (Get-Command Export-ToolkitDocumentation -ErrorAction Stop).CommandType | Should -Be 'Function'
        }

        It 'lanca excecao se OutputPath existe sem -Force' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            $null = New-Item -Path $tempDir -ItemType Directory -Force
            try {
                { Export-ToolkitDocumentation -Mode Portal -OutputPath $tempDir } | Should -Throw
            }
            finally {
                Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
            }
        }

        It 'gera index.html e operador.html com -Mode Portal' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            try {
                $result = Export-ToolkitDocumentation `
                    -Mode Portal `
                    -OutputPath $tempDir `
                    -ManualPath (Join-Path $repoRootLocal 'docs\manual') `
                    -Force
                $result.Success | Should -Be $true
                Test-Path (Join-Path $tempDir 'index.html')    | Should -Be $true
                Test-Path (Join-Path $tempDir 'operador.html') | Should -Be $true
                $content = [System.IO.File]::ReadAllText((Join-Path $tempDir 'index.html'))
                $content | Should -Match 'WBA Windows Toolkit'
            }
            finally {
                Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
            }
        }

        It 'gera referencia com -Mode TechnicalReference' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            try {
                $coreModule = Join-Path $repoRootLocal 'modules\WbaToolkit.Core\WbaToolkit.Core.psd1'
                $result = Export-ToolkitDocumentation `
                    -Mode TechnicalReference `
                    -OutputPath $tempDir `
                    -ModulePath @($coreModule) `
                    -ScriptPath @() `
                    -Force
                $result.Success | Should -Be $true
                Test-Path (Join-Path $tempDir 'referencia\index.html') | Should -Be $true
            }
            finally {
                Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
            }
        }

        It 'retorna objeto com propriedades esperadas' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            try {
                $result = Export-ToolkitDocumentation `
                    -Mode Portal `
                    -OutputPath $tempDir `
                    -ManualPath (Join-Path $repoRootLocal 'docs\manual') `
                    -Force
                $props = $result.PSObject.Properties.Name
                $props | Should -Contain 'Success'
                $props | Should -Contain 'Mode'
                $props | Should -Contain 'OutputPath'
                $props | Should -Contain 'PortalIndex'
                $props | Should -Contain 'TechnicalReferenceIndex'
                $props | Should -Contain 'WarningCount'
            }
            finally {
                Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
            }
        }
    }
}
