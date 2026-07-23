# Manual do Operador

Este é o ponto único da documentação operacional do WBA Windows Toolkit. Use-o para escolher uma ferramenta,
executar o comando e localizar o resultado. A referência técnica fica no final do documento.

## Antes de começar

Abra o PowerShell como Administrador e entre na raiz do toolkit:

```powershell
Set-Location C:\ti\wba-windows-toolkit
Set-ExecutionPolicy Bypass -Scope Process -Force
```

O `Bypass` vale somente para a sessão atual. Não altere a política permanente sem necessidade.

Para abrir o menu interativo do operador:

```powershell
.\xtudo.ps1
```

Para conhecer os parâmetros de qualquer script:

```powershell
.\scripts\nome-do-script.ps1 -Help
```

Comece pelo diagnóstico. Execute ações de limpeza, reparo ou atualização somente depois de revisar o resultado.

## Escolha pela tarefa

| Preciso... | Use | Risco |
|---|---|---|
| investigar lentidão ou disco em 100% | `diagnosticar-disco-100.ps1` | baixo |
| verificar consumo de memória | `diagnosticar-memoria.ps1` | baixo |
| testar rede, DNS e conectividade | `testar-conectividade-internet.ps1` | baixo |
| encontrar IPs duplicados | `detectar-ip-duplicado.ps1` | baixo |
| coletar dados do computador | `inventario-hardware-software.ps1` | baixo |
| analisar espaço ocupado | `analisar-espaco-disco.ps1` | baixo |
| verificar o cliente Active Directory | `diagnosticar-ad-cliente.ps1` | baixo |
| acertar relógio, fonte NTP e fuso | `sincronizar-relogio.ps1` | médio |
| limpar arquivos e componentes | `limpar-windows.ps1` ou `limpar-winsxs.ps1` | médio |
| atualizar o Windows | `atualizar-windows.ps1` | médio |
| preparar uma imagem | `preparar-imagem-windows.ps1` | alto |

## Comandos mais usados

### Diagnóstico

```powershell
.\scripts\diagnosticar-disco-100.ps1 -GerarHtml
.\scripts\diagnosticar-memoria.ps1 -GerarHtml
.\scripts\testar-conectividade-internet.ps1 -Detalhado
.\scripts\diagnosticar-ad-cliente.ps1 -GerarHtml
.\scripts\sincronizar-relogio.ps1 -GerarHtml
```

Para corrigir a fonte de tempo, use `-Corrigir`. Em computadores no domínio, a ferramenta usa a hierarquia do AD;
fora do domínio, usa `pool.ntp.br` por padrão. O fuso só é alterado quando `-TimeZoneId` é informado explicitamente.

### Rede e endereços IP

```powershell
.\scripts\detectar-ip-duplicado.ps1 -Range '192.168.4.1-190'
.\scripts\detectar-ip-duplicado.ps1 -Range '192.168.4.0/23' -OutputPath 'C:\Temp\Relatorios'
```

O relatório mostra IPs ocupados, IPs livres observados e endereços com mais de um MAC. Um IP livre é aquele sem
entrada ARP observada durante a coleta; isso não prova que o endereço esteja definitivamente disponível.

### Inventário

```powershell
.\scripts\inventario-hardware-software.ps1 -NaoPDF
.\scripts\inventario-hardware-software.ps1 -GerarResumoHardwareDrivers
```

### Manutenção

```powershell
.\scripts\limpar-windows.ps1 -NoReboot
.\scripts\limpar-winsxs.ps1 -Modo Relatorio -GerarHtml
.\scripts\limpar-winsxs.ps1 -Modo Limpeza -DryRun
.\scripts\analisar-espaco-disco.ps1 -Drive C -MaxDepth 3 -NaoPDF
```

### Atualização e preparação

```powershell
.\scripts\atualizar-windows.ps1 -Backend WinGet -Action ListOnly
.\scripts\preparar-imagem-windows.ps1 -ApenasDryRun
```

Não execute preparação de imagem ou atualização em equipamento de produção sem backup e janela de manutenção.

## Relatórios

Quando o caminho não é informado, os scripts usam a raiz configurada no toolkit ou:

```text
C:\WBA\Relatorios
```

Cada execução cria uma pasta própria com módulo e data. O parâmetro de saída varia conforme o script; confirme com
`-Help` antes de usar. Nos scripts que aceitam `-OutputPath` ou `-Path`, informe a raiz desejada para os relatórios.

Guarde o relatório e o log no chamado. Não envie chaves, senhas ou dados pessoais sem necessidade.

## Como interpretar e agir

1. Leia o resumo e confirme o equipamento analisado.
2. Separe falhas reais de avisos informativos.
3. Preserve o relatório original antes de executar uma correção.
4. Faça uma alteração por vez e registre o resultado.
5. Se houver suspeita de falha de disco, priorize backup.
6. Se a ação solicitar reinicialização, combine o horário com o usuário.

## Scripts oficiais

| Script | Finalidade |
|---|---|
| `limpar-windows.ps1` | Limpeza conservadora e manutenção do sistema |
| `limpar-winsxs.ps1` | Diagnóstico e limpeza assistida do Component Store |
| `diagnosticar-disco-100.ps1` | Investigação de uso de disco em 100% |
| `diagnosticar-memoria.ps1` | Identificação de consumo elevado de memória |
| `diagnosticar-grafico.ps1` | Diagnóstico de GPU, DWM, TDR e eventos gráficos |
| `testar-conectividade-internet.ps1` | Testes de gateway, DNS, ICMP e TCP |
| `detectar-ip-duplicado.ps1` | Varredura ARP para identificar IPs com múltiplos MACs |
| `diagnosticar-ad-cliente.ps1` | Diagnóstico de domínio, DNS e canal seguro |
| `sincronizar-relogio.ps1` | Diagnóstico e correção contextual de hora, fonte NTP e fuso |
| `verificar-atualizacoes-hardware.ps1` | Verificação de BIOS e drivers |
| `preparar-imagem-windows.ps1` | Preparação de imagem e Sysprep |
| `atualizar-windows.ps1` | Atualização do Windows e gerenciadores disponíveis |
| `gerenciar-login-automatico.ps1` | Diagnóstico e administração do autologon |
| `inventario-hardware-software.ps1` | Inventário de hardware e software |
| `analisar-espaco-disco.ps1` | Análise de pastas e arquivos por tamanho |
| `gerenciar-drivers.ps1` | Backup e restauração de drivers |
| `gerenciar-inicializacao.ps1` | Diagnóstico de inicialização e serviços |
| `configurar-idioma-regional.ps1` | Configuração de idioma, região e fuso |
| `remover-perfis-inativos.ps1` | Identificação e remoção assistida de perfis |

## Referência técnica

| Documento | Quando consultar |
|---|---|
| [`referencia/modulos.md`](referencia/modulos.md) | Módulos e funções públicas |
| [`glossario.pt-BR.md`](glossario.pt-BR.md) | Termos usados no toolkit |

### Módulos

| Módulo | Responsabilidade |
|---|---|
| `WbaToolkit.Core` | Saída, logs, sessões, relatórios e documentação |
| `WbaToolkit.Networking` | Rede, conectividade e relatórios ARP |
| `WbaToolkit.Inventory` | Inventário e cobertura de hardware/software |
| `WbaToolkit.Maintenance` | Limpeza, sistema de arquivos e imagem |
| `WbaToolkit.Startup` | Inicialização, serviços e tarefas |
| `WbaToolkit.Identity` | Identidade local e autologon |
| `WbaToolkit.Licensing` | Diagnóstico do licenciamento Windows; não expõe comandos públicos |

## Gerar documentação HTML

No Windows PowerShell 5.1:

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
Export-ToolkitDocumentation -Mode All -Force
```

O portal offline será criado em `docs/portal/`. O conteúdo desta página é a fonte operacional principal.
