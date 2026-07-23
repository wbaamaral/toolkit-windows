# Modules

Diretório dos módulos PowerShell reutilizáveis do WBA Windows Toolkit.

Os módulos concentram funções comuns usadas pelos scripts operacionais. Scripts devem importar e reutilizar essas
funções antes de criar lógica duplicada.

## Estrutura

```text
modules/
├── WbaToolkit.Core/
├── WbaToolkit.Identity/
├── WbaToolkit.Inventory/
├── WbaToolkit.Licensing/
├── WbaToolkit.Maintenance/
├── WbaToolkit.Networking/
└── WbaToolkit.Startup/
```

## Regras

- Funções públicas ficam em `Public/`.
- Funções internas ficam em `Private/`.
- O `.psm1` carrega as funções e exporta apenas as públicas.
- Funções públicas devem ter `Comment-Based Help`.
- Funções públicas devem expor ajuda inline consistente com `Get-Help`.
- Funções públicas podem declarar metadados do manual HTML com uma linha interna no formato
  `# WBA-DOCS: Category=Networking; Related=Show-ConnectivityReport; Manual=Descricao curta`.

## `WbaToolkit.Core`

Módulo base do projeto. Funções comuns de console, segurança, configuração, relatórios e documentação.

| Função | Uso |
|---|---|
| `Test-IsAdministrator` | Verifica se a sessão está elevada |
| `Invoke-Safe` | Executa blocos com tratamento padronizado de erro |
| `Invoke-ExternalCommand` | Executa comandos externos com controle de saída |
| `Read-YesNo` | Pergunta Sim/Não ao operador |
| `Write-Ok`, `Write-Fail`, `Write-Warn`, `Write-Info` | Mensagens padronizadas |
| `Write-Title`, `Write-Section`, `Write-Step` | Estrutura visual de console |
| `Write-ScriptLog` | Log estruturado em arquivo |
| `Format-FileSize` | Formatação legível de tamanhos |
| `ConvertTo-HtmlSafe` | Escape seguro para HTML |
| `Write-TextFileUtf8` | Escrita de arquivos UTF-8 com BOM |
| `Get-ToolkitConfiguration` | Lê configuração persistente |
| `Set-ToolkitReportsRoot` | Salva raiz padrão de relatórios |
| `Get-ToolkitReportsRoot` | Resolve a raiz de relatórios por precedência |
| `Initialize-ToolkitReportSession` | Cria diretório de sessão padronizado |
| `Initialize-ScriptSession` | Wrapper com StartedAt e Mode |
| `Get-CimInstanceSafe` | Consulta CIM com tratamento de erro |
| `New-ToolkitElevationCommand` | Gera comando para elevação de privilégios |
| `Export-ToolkitFunctionDocs` | Gera manual HTML local dos scripts e funções |
| `Export-ToolkitDocumentation` | Gera portal HTML documentação |
| `New-ToolkitHtmlReport` | Template HTML compartilhado para relatórios |
| `Sync-ComputerTime` | Diagnóstico e correção contextual da fonte de tempo e fuso |
| `Show-Spinner` | Spinner com timer para operações longas |
| `Get-FileHashSha256` | Hash SHA256 de arquivos |
| `New-ToolkitArchive` | Empacotamento ZIP com hash SHA256 |
| `Get-ReportLogoBase64` | Retorna logo do toolkit em base64 |

## `WbaToolkit.Licensing`

Módulo interno para diagnóstico do licenciamento Windows. Não exporta funções públicas; os helpers são usados por
rotinas de suporte e seguem as APIs oficiais do sistema.

## `WbaToolkit.Networking`

Módulo de testes de rede e conectividade.

| Função | Uso |
|---|---|
| `Get-NetworkContext` | Coleta interface ativa, IP, gateway e DNS |
| `Invoke-ConnectivityTest` | Executa diagnóstico geral de conectividade |
| `Invoke-ConnectivityWizard` | Abre wizard do diagnóstico geral |
| `New-ConnectivityTestPlan` | Monta plano padrão de testes |
| `Test-GatewayConnectivity` | Testa comunicação com gateway |
| `Test-DnsResolution` | Testa resolução DNS |
| `Test-IcmpConnectivity` | Testa ICMP |
| `Test-TcpPortConnectivity` | Testa porta TCP |
| `Test-UdpPortConnectivity` | Testa UDP |
| `Test-LocalTcpListener` | Verifica porta TCP local escutando |
| `Test-LocalUdpListener` | Verifica endpoint UDP local |
| `Test-DownloadSpeed` | Testa velocidade de download |
| `Invoke-TargetConnectivityTest` | Testa alvo informado |
| `Invoke-TargetConnectivityWizard` | Wizard interativo para alvo |
| `Show-ConnectivityReport` | Exibe relatório no console |
| `Export-ConnectivityReport` | Exporta relatório HTML |
| `Export-ConnectivityReportPdf` | Exporta PDF |

## `WbaToolkit.Startup`

Módulo de gerenciamento de inicialização do Windows.

| Função | Uso |
|---|---|
| `Get-StartupItems` | Lista itens de inicialização |
| `Enable-StartupItem` | Habilita item de inicialização |
| `Disable-StartupItem` | Desabilita item de inicialização |
| `Remove-StartupItem` | Remove item de inicialização |
| `Get-ManagedDisabledStartupItems` | Lista itens desabilitados pelo toolkit |

## `WbaToolkit.Maintenance`

Módulo de manutenção, limpeza e preparação de imagem.

| Função | Uso |
|---|---|
| `Get-DiskInfo` | Informações de disco |
| `Get-FilesystemErrorEvent` | Eventos de erro do sistema de arquivos |
| `Write-MaintenanceEvent` | Registra evento de manutenção |
| `Invoke-FilesystemCheck` | Verificação do sistema de arquivos |
| `Invoke-EventLogMaintenance` | Limpeza do visualizador de eventos |
| `Get-ComponentStoreInfo` | Analisa WinSxS via DISM |
| `Invoke-ComponentStoreCleanup` | Limpa Component Store via DISM |
| `Test-SysprepEnvironment` | Verifica ambiente para Sysprep |
| `Invoke-RegFileImport` | Importa arquivos .reg de forma segura |

## `WbaToolkit.Identity`

Módulo de gerenciamento de identidade e logon automático.

| Função | Uso |
|---|---|
| `Get-AutologonStatus` | Verifica status do logon automático |
| `Enable-Autologon` | Habilita logon automático |
| `Disable-Autologon` | Desabilita logon automático |
| `Set-Autologon` | Configura logon automático |
| `Invoke-AutologonManager` | Gerencia logon automático |

## `WbaToolkit.Inventory`

Módulo de inventário técnico do toolkit.

| Função | Uso |
|---|---|
| `Get-InventoryCoverageMap` | Retorna cobertura do inventário |

## Documentação HTML

As funções públicas devem manter ajuda baseada em comentários (`Comment-Based Help`). Quando a função precisar
aparecer melhor organizada no manual HTML, inclua uma linha `WBA-DOCS` em comentário interno.

Exemplo:

```powershell
# WBA-DOCS: Category=Core; Related=Get-ToolkitReportsRoot; Manual=Define a raiz padrao de relatorios.
```

Para gerar o manual local:

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
Export-ToolkitFunctionDocs -OutputPath .\docs-html -Force
```
