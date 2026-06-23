# Modules

Diretório dos módulos PowerShell reutilizáveis do WBA Windows Toolkit.

Os módulos concentram funções comuns usadas pelos scripts operacionais. Scripts devem importar e reutilizar essas
funções antes de criar lógica duplicada.

## Estrutura

```text
modules/
├── WbaToolkit.Core/
    ├── WbaToolkit.Core.psd1
    ├── WbaToolkit.Core.psm1
    ├── Public/
    └── Private/
└── WbaToolkit.Networking/
    ├── WbaToolkit.Networking.psd1
    ├── WbaToolkit.Networking.psm1
    ├── Public/
	    └── Private/
```

## Regras

- Funções públicas ficam em `Public/`.
- Funções internas ficam em `Private/`.
- O `.psm1` carrega as funções e exporta apenas as públicas.
- Funções públicas devem ter `Comment-Based Help`.
- Funções públicas devem expor ajuda inline consistente com `Get-Help`, incluindo suporte a `-Help` quando a função for invocada diretamente por script de operação.
- Funções públicas podem declarar metadados do manual HTML com uma linha interna no formato
  `# WBA-DOCS: Category=Networking; Related=Show-ConnectivityReport; Manual=Descrição curta`.
- A decisão formal dessa padronização está na ADR 0021.

## `WbaToolkit.Core`

Módulo base do projeto. Deve ser preferido para comportamento comum de console, segurança, configuração, relatórios e
documentação.

Funções públicas principais:

| Função | Uso |
|---|---|
| `Test-IsAdministrator` | Verifica se a sessão está elevada |
| `Invoke-Safe` | Executa blocos com tratamento padronizado de erro |
| `Invoke-ExternalCommand` | Executa comandos externos com controle de saída |
| `Read-YesNo` | Pergunta Sim/Não ao operador |
| `Write-Ok`, `Write-Fail`, `Write-Warn`, `Write-Info` | Mensagens padronizadas |
| `Write-Title`, `Write-Section`, `Write-StatusLine` | Estrutura visual de console |
| `Format-FileSize` | Formatação legível de tamanhos |
| `ConvertTo-HtmlSafe` | Escape seguro para HTML |
| `Get-ToolkitConfiguration` | Lê configuração persistente |
| `Set-ToolkitReportsRoot` | Salva raiz padrão de relatórios |
| `Get-ToolkitReportsRoot` | Resolve a raiz de relatórios por precedência |
| `Initialize-ToolkitReportSession` | Cria diretório de sessão padronizado |
| `Export-ToolkitFunctionDocs` | Gera manual HTML local dos scripts e funções |

## `WbaToolkit.Networking`

Módulo de testes de rede e conectividade.

Funções públicas principais:

| Função | Uso |
|---|---|
| `Get-NetworkContext` | Coleta interface ativa, IP, gateway e DNS |
| `Invoke-ConnectivityTest` | Executa diagnóstico geral de conectividade com internet |
| `Invoke-ConnectivityWizard` | Abre wizard do diagnóstico geral |
| `New-ConnectivityTestPlan` | Monta plano padrão de testes |
| `Test-GatewayConnectivity` | Testa comunicação com gateway |
| `Test-DnsResolution` | Testa resolução DNS |
| `Test-IcmpConnectivity` | Testa ICMP |
| `Test-TcpPortConnectivity` | Testa porta TCP |
| `Test-UdpPortConnectivity` | Testa UDP |
| `Test-LocalTcpListener` | Verifica porta TCP local escutando |
| `Test-LocalUdpListener` | Verifica endpoint UDP local |
| `Invoke-TargetConnectivityTest` | Testa alvo informado com protocolo e portas |
| `Invoke-TargetConnectivityWizard` | Wizard interativo para alvo, protocolo e portas |
| `Show-ConnectivityReport` | Exibe relatório no console |
| `Export-ConnectivityReport` | Exporta relatório HTML |
| `Export-ConnectivityReportPdf` | Exporta PDF quando suportado |

## Documentação HTML

As funções públicas devem manter ajuda baseada em comentários (`Comment-Based Help`). Quando a função precisar
aparecer melhor organizada no manual HTML, inclua uma linha `WBA-DOCS` em comentário interno.

Exemplo:

```powershell
# WBA-DOCS: Category=Core; Related=Get-ToolkitReportsRoot; Manual=Define a raiz padrão de relatórios.
```

Para gerar o manual local:

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
Export-ToolkitFunctionDocs -OutputPath .\docs-html -Force
```
