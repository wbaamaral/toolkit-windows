# Referência de Módulos — WBA Windows Toolkit

Autor: **wbaamaral**

Para o portal HTML completo (portal operacional + referência técnica CBH), execute `Export-ToolkitDocumentation` no Windows.
Para apenas a referência técnica CBH, execute `Export-ToolkitFunctionDocs`.

## WbaToolkit.Core

Módulo base. Fornece funções compartilhadas por todos os scripts e módulos.

Localização: `modules/WbaToolkit.Core/WbaToolkit.Core.psm1`

### Saída padronizada

| Função | Descrição |
|---|---|
| `Write-Ok` | Saída com indicador de sucesso |
| `Write-Fail` | Saída com indicador de falha |
| `Write-Warn` | Saída com indicador de aviso |
| `Write-Info` | Saída informativa |
| `Write-Title` | Cabeçalho de seção principal |
| `Write-Section` | Cabeçalho de subseção |

### Entrada do usuário

| Função | Descrição |
|---|---|
| `Read-YesNo` | Confirmar ação com Sim/Não |
| `Read-UserInput` | Ler entrada de texto com prompt |

### Execução e segurança

| Função | Descrição |
|---|---|
| `Test-IsAdministrator` | Verifica se a sessão é elevada |
| `Invoke-Safe` | Executa bloco com tratamento de erro padronizado |
| `Invoke-ExternalCommand` | Executa comando externo com captura de saída |
| `Get-CimInstanceSafe` | Consulta CIM com fallback seguro |

### Sessão e logging

| Função | Descrição |
|---|---|
| `Initialize-ScriptSession` | Inicializa contexto padronizado de sessão |
| `Initialize-ToolkitReportSession` | Cria estrutura de pastas para relatório |
| `Write-ScriptLog` | Registra mensagem em arquivo de log e console |

### Configuração e relatórios

| Função | Descrição |
|---|---|
| `Get-ToolkitConfiguration` | Lê configuração persistente do toolkit |
| `Set-ToolkitReportsRoot` | Define pasta padrão de relatórios |
| `Get-ToolkitReportsRoot` | Retorna pasta padrão de relatórios |

### Utilitários

| Função | Descrição |
|---|---|
| `Format-FileSize` | Formata bytes em unidade legível |
| `Get-Utf8BomEncoding` | Retorna encoding UTF-8 com BOM |
| `Write-TextFileUtf8` | Escreve arquivo texto em UTF-8 com BOM |
| `ConvertTo-HtmlSafe` | Escapa conteúdo para uso em HTML |
| `Export-ToolkitFunctionDocs` | Gera HTML de referência técnica com CBH das funções |
| `Export-ToolkitDocumentation` | Gera portal HTML offline completo (portal operacional + referência técnica) |

## WbaToolkit.Networking

Diagnóstico de conectividade, testes de rede e exportação de relatórios.

Localização: `modules/WbaToolkit.Networking/WbaToolkit.Networking.psm1`

| Função | Descrição |
|---|---|
| `Get-NetworkContext` | Contexto da interface de rede ativa |
| `Test-GatewayConnectivity` | Testa conectividade com o gateway |
| `Test-DnsResolution` | Teste de resolução DNS |
| `Test-IcmpConnectivity` | Teste de ping ICMP |
| `Test-TcpPortConnectivity` | Teste de porta TCP |
| `Test-UdpPortConnectivity` | Teste de porta UDP |
| `Test-LocalTcpListener` | Verifica listener TCP local |
| `Test-LocalUdpListener` | Verifica listener UDP local |
| `New-ConnectivityTestPlan` | Cria plano de testes de conectividade |
| `Invoke-ConnectivityTest` | Executa plano de testes |
| `Invoke-ConnectivityWizard` | Wizard interativo de conectividade |
| `Invoke-TargetConnectivityTest` | Testa conectividade direcionada a alvo |
| `Invoke-TargetConnectivityWizard` | Wizard de teste direcionado por alvo |
| `Show-ConnectivityReport` | Exibe relatório de conectividade no console |
| `Export-ConnectivityReport` | Exporta relatório HTML de conectividade |
| `Export-ConnectivityReportPdf` | Exporta relatório para PDF |

## WbaToolkit.Startup

Gerenciamento de itens de inicialização do Windows.

Localização: `modules/WbaToolkit.Startup/WbaToolkit.Startup.psm1`

| Função | Descrição |
|---|---|
| `Get-StartupItem` | Lista itens de inicialização |
| `Show-StartupItem` | Exibe itens de inicialização no console |
| `Disable-StartupItem` | Desabilita item de inicialização |
| `Enable-StartupItem` | Reabilita item de inicialização |
| `Remove-StartupItem` | Remove item de inicialização |
| `Invoke-StartupManager` | Ferramenta interativa de gerenciamento de startup |
| `Get-ServiceStartupState` | Retorna tipo de inicialização de um serviço |

## WbaToolkit.Maintenance

Manutenção avançada do sistema: limpeza de arquivos, WinSxS, sistema de arquivos, logs de eventos e preparação de imagem corporativa.

Localização: `modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psm1`

### Sysprep e imagem corporativa

| Função | Descrição |
|---|---|
| `Get-DefaultUserHivePath` | Localiza hive do perfil Default |
| `Invoke-WithDefaultUserHive` | Executa bloco com hive Default montado em `HKU\WBA_DefaultProfile` |
| `Import-RegistryTweakToDefaultProfile` | Importa arquivo `.reg` para o perfil Default |
| `Test-SysprepEnvironment` | Valida pré-requisitos para sysprep corporativo |
| `Invoke-SysprepPreparation` | Orquestra tweaks e dispara sysprep |

### Limpeza e sistema de arquivos

| Função | Descrição |
|---|---|
| `Remove-SafePath` | Remove arquivos de um diretório com filtro opcional por idade |
| `Get-DiskInfo` | Retorna tamanho e espaço livre do SystemDrive via WMI |
| `Get-FilesystemErrorEvent` | Consulta eventos de erro/falha no log System |
| `Write-MaintenanceEvent` | Registra evento no Visualizador de Eventos com fonte parametrizada |
| `Invoke-FilesystemCheck` | Verifica eventos de falha no sistema de arquivos e agenda chkdsk |
| `Invoke-EventLogMaintenance` | Limpa logs do Visualizador de Eventos com backup opcional de erros |

### Component Store (WinSxS)

| Função | Descrição |
|---|---|
| `Get-ComponentStoreInfo` | Analisa Component Store via DISM AnalyzeComponentStore |
| `Invoke-ComponentStoreCleanup` | Executa limpeza do WinSxS via DISM com suporte a DryRun e ResetBase |

## WbaToolkit.Identity

Identidade e acesso local do Windows. Primeira frente: gerenciamento do logon automático (autologon)
com a senha protegida por segredo LSA (ADR 0023), nunca em texto claro no registro (ADR 0005).

Localização: `modules/WbaToolkit.Identity/WbaToolkit.Identity.psm1`

### Autologon

| Função | Descrição |
|---|---|
| `Get-AutologonStatus` | Lê o estado do autologon (somente leitura); reporta presença da senha na LSA sem revelá-la |
| `Enable-Autologon` | Habilita o autologon; grava a senha como segredo LSA; backup, AutoLogonCount, -DryRun/-WhatIf |
| `Disable-Autologon` | Desabilita o autologon e limpa o segredo LSA |
| `Set-Autologon` | Edita usuário/domínio/senha/AutoLogonCount sem alternar o estado |
| `Invoke-AutologonManager` | Gerenciador interativo (habilitar/desabilitar/editar) |
