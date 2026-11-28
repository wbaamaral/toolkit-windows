#requires -version 5.1

# BCK-070: funcoes publicas do WbaToolkit.Core sem teste dedicado, incluindo
# New-ToolkitElevationCommand (ADR 0025), antes coberta so indiretamente pelos testes de Licensing.

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'modules\WbaToolkit.Core\WbaToolkit.Core.psd1') -Force
}

Describe 'ConvertTo-HtmlSafe' {
    It 'Escapa os caracteres especiais de HTML' {
        ConvertTo-HtmlSafe -Value '<a href="x">R&D</a>' | Should -Be '&lt;a href=&quot;x&quot;&gt;R&amp;D&lt;/a&gt;'
    }

    It 'Escapa o & antes das demais entidades, sem escapar duas vezes' {
        ConvertTo-HtmlSafe -Value '&lt;' | Should -Be '&amp;lt;'
    }

    It 'Devolve o padrao para nulo, vazio ou so espacos' {
        ConvertTo-HtmlSafe -Value $null | Should -Be '<span class="text-gray-500">&mdash;</span>'
        ConvertTo-HtmlSafe -Value '   ' -Default 'n/d' | Should -Be 'n/d'
    }

    It 'Converte valores nao textuais' {
        ConvertTo-HtmlSafe -Value 42 | Should -Be '42'
    }
}

Describe 'Format-FileSize' {
    It 'Formata <Bytes> bytes como <Esperado>' -ForEach @(
        @{ Bytes = 0; Esperado = '0 B' }
        @{ Bytes = 1023; Esperado = '1023 B' }
        @{ Bytes = 1536; Esperado = ('{0:N1} KB' -f 1.5) }
        @{ Bytes = 5MB; Esperado = ('{0:N1} MB' -f 5) }
        @{ Bytes = 3GB; Esperado = ('{0:N2} GB' -f 3) }
        @{ Bytes = 2TB; Esperado = ('{0:N2} TB' -f 2) }
    ) {
        Format-FileSize -Bytes $Bytes | Should -Be $Esperado
    }

    It 'Recusa valor negativo' {
        { Format-FileSize -Bytes -1 } | Should -Throw
    }
}

Describe 'Get-ReportLogoBase64' {
    It 'Converte SVG em data URI' {
        $logo = Join-Path $TestDrive 'logo.svg'
        [System.IO.File]::WriteAllText($logo, '<svg/>')

        Get-ReportLogoBase64 -LogoPath $logo | Should -Be ('data:image/svg+xml;base64,' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('<svg/>')))
    }

    It 'Usa o MIME correto para JPG' {
        $logo = Join-Path $TestDrive 'logo.jpeg'
        [System.IO.File]::WriteAllBytes($logo, [byte[]](1, 2, 3))

        Get-ReportLogoBase64 -LogoPath $logo | Should -Be 'data:image/jpeg;base64,AQID'
    }

    It 'Devolve nulo quando o arquivo nao existe' {
        Get-ReportLogoBase64 -LogoPath (Join-Path $TestDrive 'nao-existe.svg') | Should -BeNullOrEmpty
    }

    It 'Recusa formato nao suportado com aviso' {
        $logo = Join-Path $TestDrive 'logo.gif'
        [System.IO.File]::WriteAllBytes($logo, [byte[]](1))

        Get-ReportLogoBase64 -LogoPath $logo -WarningVariable avisos -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        $avisos | Should -Match 'nao suportado'
    }

    It 'Avisa sobre logo grande, mas devolve a imagem' {
        $logo = Join-Path $TestDrive 'grande.png'
        [System.IO.File]::WriteAllBytes($logo, [byte[]]::new(21KB))

        $uri = Get-ReportLogoBase64 -LogoPath $logo -WarningVariable avisos -WarningAction SilentlyContinue
        $uri | Should -Match '^data:image/png;base64,'
        $avisos | Should -Match 'tamanho maximo'
    }

    It 'Sem -LogoPath procura assets\images\logo.svg na raiz do toolkit' {
        Mock -ModuleName WbaToolkit.Core Test-Path { $false }

        Get-ReportLogoBase64 | Should -BeNullOrEmpty

        $esperado = Join-Path $script:repoRoot 'assets\images\logo.svg'
        Should -Invoke -ModuleName WbaToolkit.Core Test-Path -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $esperado }
    }
}

Describe 'Get-ToolkitConfiguration e Set-ToolkitReportsRoot' {
    BeforeEach {
        $script:configPath = Join-Path $TestDrive ("cfg{0}\config.json" -f [guid]::NewGuid().ToString('N'))
    }

    It 'Sem arquivo devolve configuracao vazia com o caminho esperado' {
        $config = Get-ToolkitConfiguration -ConfigPath $script:configPath

        $config.ConfigPath | Should -Be $script:configPath
        @($config.PSObject.Properties).Count | Should -Be 1
    }

    It 'Sem -ConfigPath usa ProgramData\WBA\WindowsToolkit\config.json' {
        $salvo = $env:ProgramData
        try {
            $env:ProgramData = Join-Path $TestDrive 'pd'
            (Get-ToolkitConfiguration).ConfigPath | Should -Be (Join-Path $TestDrive 'pd\WBA\WindowsToolkit\config.json')
        } finally {
            $env:ProgramData = $salvo
        }
    }

    It 'Le o JSON existente' {
        New-Item -Path (Split-Path -Parent $script:configPath) -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($script:configPath, '{"ReportsRoot":"D:\\Rel","Outro":1}')

        $config = Get-ToolkitConfiguration -ConfigPath $script:configPath
        $config.ReportsRoot | Should -Be 'D:\Rel'
        $config.Outro | Should -Be 1
    }

    It 'Falha com mensagem clara quando o JSON esta corrompido' {
        New-Item -Path (Split-Path -Parent $script:configPath) -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($script:configPath, '{ isto nao e json')

        { Get-ToolkitConfiguration -ConfigPath $script:configPath } | Should -Throw '*Nao foi possivel ler a configuracao*'
    }

    It 'Set-ToolkitReportsRoot cria o arquivo, preserva outras chaves e nao grava ConfigPath' {
        New-Item -Path (Split-Path -Parent $script:configPath) -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($script:configPath, '{"Outro":"valor"}')
        $destino = Join-Path $TestDrive 'Relatorios'

        $r = Set-ToolkitReportsRoot -Path $destino -ConfigPath $script:configPath -Confirm:$false

        $r.Success | Should -BeTrue
        $r.ReportsRoot | Should -Be $destino
        $json = Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json
        $json.ReportsRoot | Should -Be $destino
        $json.Outro | Should -Be 'valor'
        $json.PSObject.Properties['ConfigPath'] | Should -BeNullOrEmpty
    }

    It 'Set-ToolkitReportsRoot cria a pasta da configuracao quando ela nao existe' {
        Set-ToolkitReportsRoot -Path (Join-Path $TestDrive 'R') -ConfigPath $script:configPath -Confirm:$false | Out-Null

        (Get-ToolkitConfiguration -ConfigPath $script:configPath).ReportsRoot | Should -Be (Join-Path $TestDrive 'R')
    }

    It 'Set-ToolkitReportsRoot -WhatIf nao grava nada' {
        Set-ToolkitReportsRoot -Path (Join-Path $TestDrive 'R') -ConfigPath $script:configPath -WhatIf | Should -BeNullOrEmpty

        Test-Path -LiteralPath $script:configPath | Should -BeFalse
    }
}

Describe 'Get-Utf8BomEncoding' {
    It 'Devolve UTF-8 que emite BOM' {
        $enc = Get-Utf8BomEncoding

        $enc | Should -BeOfType [System.Text.UTF8Encoding]
        $enc.GetPreamble() | Should -Be ([byte[]](0xEF, 0xBB, 0xBF))
    }
}

Describe 'Initialize-ScriptSession' {
    It 'Cria a sessao sob <raiz>\<modulo> com a pasta de logs' {
        $raiz = Join-Path $TestDrive 'Rel'

        $s = Initialize-ScriptSession -ModuleName 'HD100' -BasePath $raiz -ExecutionMode 'Diagnostico'

        $s.Mode | Should -Be 'Diagnostico'
        $s.ReportsRoot | Should -Be $raiz
        $s.BasePath | Should -Be (Join-Path $raiz 'HD100')
        (Split-Path -Parent $s.Path) | Should -Be $s.BasePath
        $s.LogsPath | Should -Be (Join-Path $s.Path 'logs')
        $s.BackupsPath | Should -Be (Join-Path $s.Path 'backups')
        Test-Path -LiteralPath $s.LogsPath -PathType Container | Should -BeTrue
        $s.StartedAt | Should -BeOfType [datetime]
    }

    It 'Exige o nome do modulo' {
        { Initialize-ScriptSession -ModuleName '' } | Should -Throw
    }
}

Describe 'Invoke-Safe' {
    It 'Devolve verdadeiro quando o bloco conclui' {
        $script:executou = $false
        Invoke-Safe -Description 'ok' -Command { $script:executou = $true } | Should -BeTrue
        $script:executou | Should -BeTrue
    }

    It 'Devolve falso e escreve erro quando o bloco lanca excecao' {
        $r = Invoke-Safe -Description 'quebra' -Command { throw 'boom' } -ErrorVariable erros -ErrorAction SilentlyContinue

        $r | Should -BeFalse
        "$erros" | Should -Match "Falha em 'quebra'.*boom"
    }

    It 'Devolve falso com aviso quando um comando nativo sai com codigo diferente de zero' {
        $r = Invoke-Safe -Description 'nativo' -Command { cmd.exe /c exit 3 } -WarningVariable avisos -WarningAction SilentlyContinue

        $r | Should -BeFalse
        $avisos | Should -Match 'codigo de saida 3'
    }

    It 'Nao herda um codigo de saida anterior' {
        cmd.exe /c exit 5
        Invoke-Safe -Description 'limpo' -Command { $null = 1 } | Should -BeTrue
    }
}

Describe 'Write-Section e Write-Step' {
    BeforeEach {
        $script:linhas = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName WbaToolkit.Core Write-Host { $script:linhas.Add([string]$Object) }
    }

    It 'Write-Section escreve o titulo entre separadores' {
        Write-Section -Title 'Diagnostico'

        $script:linhas | Should -Be @('', ('=' * 60), ' Diagnostico', ('=' * 60))
    }

    It 'Write-Step escreve [NN%] mensagem' {
        Write-Step 'Limpando temporarios' 25

        $script:linhas | Should -Be @('', '[25%] Limpando temporarios')
    }

    It 'Write-Step recusa percentual fora de 0 a 100' {
        { Write-Step 'x' 101 } | Should -Throw
    }
}

Describe 'New-ToolkitElevationCommand (ADR 0025)' {
    It 'Mantem valores simples legiveis, entre aspas simples' {
        $cmd = New-ToolkitElevationCommand -ScriptPath 'C:\WBA\script.ps1' -BoundParameters ([ordered]@{ Modo = 'Diagnostico'; Dias = 30 })

        $cmd | Should -Be "& 'C:\WBA\script.ps1' -Modo 'Diagnostico' -Dias '30'"
    }

    It 'Inclui switch ligado, omite switch desligado e array vazio' {
        $bp = [ordered]@{ Forcar = [switch]$true; Silencioso = [switch]$false; Drive = @() }

        New-ToolkitElevationCommand -ScriptPath 'C:\s.ps1' -BoundParameters $bp | Should -Be "& 'C:\s.ps1' -Forcar"
    }

    It 'Escapa aspas simples' {
        New-ToolkitElevationCommand -ScriptPath "C:\pasta d'x\s.ps1" -BoundParameters @{ Nome = "O'Neil" } |
            Should -Be "& 'C:\pasta d''x\s.ps1' -Nome 'O''Neil'"
    }

    It 'Preserva no processo relancado valores com espacos, aspas, tabulacao, acentos e arrays' {
        # Mesmo transporte dos scripts: Start-Process powershell.exe -ArgumentList @(..., '-Command', $cmd).
        $pasta = Join-Path $TestDrive "pasta d'elevacao"
        New-Item -Path $pasta -ItemType Directory -Force | Out-Null
        $sonda = Join-Path $pasta 'sonda.ps1'
        $corpo = 'param([string]$Nome, [string[]]$Drive, [switch]$Forcar, [int]$Dias, [string]$Saida) ' +
            '[System.IO.File]::WriteAllText($Saida, ([pscustomobject]@{ Nome = $Nome; Drive = $Drive; Forcar = [bool]$Forcar; Dias = $Dias } | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))'
        [System.IO.File]::WriteAllText($sonda, $corpo, [System.Text.UTF8Encoding]::new($true))
        $saida = Join-Path $pasta 'saida.json'
        $bp = [ordered]@{
            Nome   = "a  b 'c' `"d`"`t`$env:USERNAME ; Relat$([char]0x00F3)rios"
            Drive  = @('C:', '"D: e"')
            Forcar = [switch]$true
            Dias   = 7
            Saida  = $saida
        }

        $cmd = New-ToolkitElevationCommand -ScriptPath $sonda -BoundParameters $bp
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) -Wait -WindowStyle Hidden

        $r = [System.IO.File]::ReadAllText($saida) | ConvertFrom-Json
        $r.Nome | Should -BeExactly $bp.Nome
        $r.Drive | Should -Be @('C:', '"D: e"')
        $r.Forcar | Should -BeTrue
        $r.Dias | Should -Be 7
    }
}
