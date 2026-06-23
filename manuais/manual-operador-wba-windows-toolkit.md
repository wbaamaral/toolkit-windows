---
title: "Manual do Operador - WBA Windows Toolkit"
author: "WBA Windows Toolkit"
lang: "pt-BR"
date: "2026-06-14"
---

# Manual do Operador - WBA Windows Toolkit

Este documento foi escrito para equipes de suporte e operadores que precisam executar rotinas do WBA Windows
Toolkit com segurança.

No estado atual do projeto, a entrada recomendada para o operador é `.\xtudo.ps1`.
O MVP expõe cinco ações principais:

- Limpar Windows
- Diagnosticar disco 100%
- Diagnosticar memória
- Diagnosticar gráfico
- Preparar imagem

O objetivo é explicar:

- como abrir o PowerShell no local correto;
- como liberar a execução temporária de scripts;
- como importar módulos;
- como listar e chamar os comandos dos módulos;
- como configurar a pasta padrão de relatórios;
- como gerar o manual HTML local;
- como operar os principais scripts de diagnóstico, inventário, manutenção e atualização;
- onde encontrar logs, relatórios e arquivos gerados.

## 1. Conceitos básicos

### 1.1. O que é o WBA Windows Toolkit

O WBA Windows Toolkit é um conjunto de scripts e módulos PowerShell para manutenção, diagnóstico, atualização e
documentação de computadores Windows.

Ele é organizado em pastas:

| Pasta | Finalidade |
|---|---|
| `scripts` | Atalhos oficiais do MVP chamados pelo `xtudo.ps1` |
| `modules` | Funções reutilizáveis usadas pelos scripts |
| `manuais` | Documentação do operador e referência rápida |
| `experimental` | Legado e ferramentas fora do fluxo principal |
| `tests` | Testes e cenários de validação |
| `docs` | Artefatos de documentação e suporte |

### 1.2. O que é um script

Um script PowerShell é um arquivo com extensão `.ps1`. Ele executa uma tarefa administrativa.

Exemplos:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1
.\experimental\maintenance\limpeza-windows.ps1
.\experimental\updates\upgrade-windows.ps1
```

### 1.3. O que é um módulo

Um módulo PowerShell é um pacote de funções. Ele não é executado como um script comum. Primeiro ele é importado,
depois suas funções ficam disponíveis para uso.

Exemplos de módulos do projeto:

| Módulo | Finalidade |
|---|---|
| `WbaToolkit.Core` | Funções comuns: mensagens, segurança, formatação, portal HTML |
| `WbaToolkit.Networking` | Diagnóstico de conectividade e relatórios de rede |
| `WbaToolkit.Startup` | Gerenciamento de itens de inicialização e serviços do Windows |

Caminhos para importação:

```powershell
modules\WbaToolkit.Core\WbaToolkit.Core.psd1
modules\WbaToolkit.Networking\WbaToolkit.Networking.psd1
modules\WbaToolkit.Startup\WbaToolkit.Startup.psd1
```

### 1.4. Quando usar PowerShell como Administrador

Use PowerShell como Administrador quando o script puder alterar o sistema.

Exemplos:

- limpeza de cache do Windows Update;
- execução de SFC, DISM e CHKDSK;
- alteração de programas de inicialização;
- atualização com Chocolatey;
- consulta ou alteração de tarefas agendadas.

Se o script precisar de elevação, ele tentará abrir uma nova janela administrativa automaticamente. Mesmo assim,
é mais simples iniciar já como Administrador.

## 2. Como abrir e preparar o PowerShell

### 2.1. Abrir PowerShell como Administrador

1. Clique no menu Iniciar.
2. Digite `PowerShell`.
3. Clique com o botão direito em `Windows PowerShell`.
4. Selecione `Executar como administrador`.

### 2.2. Entrar na pasta do toolkit

Exemplo usando `C:\ti\wba-windows-toolkit`:

```powershell
Set-Location C:\ti\wba-windows-toolkit
```

Confirme que está na pasta correta:

```powershell
Get-Location
```

Liste os arquivos:

```powershell
Get-ChildItem
```

Você deve ver pastas como `maintenance`, `updates`, `modules` e `docs`.

### 2.3. Liberar execução de scripts somente nesta janela

Se o Windows bloquear a execução, rode:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

Essa liberação vale somente para a janela atual do PowerShell. Ao fechar a janela, a política normal do Windows
continua preservada.

## 3. Como importar módulos

### 3.1. Importar o módulo principal

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
```

### 3.2. Importar o módulo de rede

```powershell
Import-Module .\modules\WbaToolkit.Networking\WbaToolkit.Networking.psd1 -Force
```

### 3.3. Importar o módulo de inicialização

```powershell
Import-Module .\modules\WbaToolkit.Startup\WbaToolkit.Startup.psd1 -Force
```

### 3.4. Ver quais comandos um módulo carregou

Para o módulo principal:

```powershell
Get-Command -Module WbaToolkit.Core
```

Para o módulo de rede:

```powershell
Get-Command -Module WbaToolkit.Networking
```

Para o módulo de inicialização:

```powershell
Get-Command -Module WbaToolkit.Startup
```

### 3.5. Pedir ajuda de uma função

Exemplo:

```powershell
Get-Help Export-ToolkitFunctionDocs -Full
```

Outro exemplo:

```powershell
Get-Help Invoke-TargetConnectivityWizard -Full
```

## 4. Subcomandos dos módulos

Neste projeto, “subcomandos dos módulos” significa as funções exportadas pelos módulos. Depois de importar um
módulo, essas funções podem ser chamadas diretamente no PowerShell.

### 4.1. Funções do módulo `WbaToolkit.Core`

| Função | Para que serve |
|---|---|
| `Test-IsAdministrator` | Verifica se o PowerShell está em modo Administrador |
| `Invoke-Safe` | Executa um bloco de comando com tratamento de erro |
| `Format-FileSize` | Mostra tamanhos de arquivo em formato legível |
| `Write-Ok` | Escreve mensagem de sucesso |
| `Write-Fail` | Escreve mensagem de erro |
| `Write-Warn` | Escreve aviso |
| `Write-Info` | Escreve informação |
| `Write-Title` | Escreve título no console |
| `Write-Section` | Escreve seção no console |
| `Read-YesNo` | Pergunta Sim/Não ao operador |
| `Invoke-ExternalCommand` | Executa comando externo com controle |
| `ConvertTo-HtmlSafe` | Escapa texto para HTML |
| `Get-ToolkitConfiguration` | Lê a configuração persistente do toolkit |
| `Set-ToolkitReportsRoot` | Salva a raiz padrão de relatórios |
| `Get-ToolkitReportsRoot` | Resolve a raiz de relatórios a ser usada |
| `Initialize-ToolkitReportSession` | Cria uma sessão padronizada de relatório |
| `Export-ToolkitFunctionDocs` | Gera referência HTML das funções com CBH |
| `Export-ToolkitDocumentation` | Gera portal HTML offline completo (modos All, Portal, TechnicalReference) |
| `Read-UserInput` | Solicita entrada do operador com suporte a valor padrão |
| `Get-Utf8BomEncoding` | Retorna encoding UTF-8 com BOM para gravação de arquivos |
| `Write-TextFileUtf8` | Grava ou acrescenta texto em arquivo UTF-8 com BOM |
| `Write-ScriptLog` | Registra mensagem de log com timestamp e nível de severidade |
| `Initialize-ScriptSession` | Cria sessão padronizada de script com caminhos resolvidos |
| `Get-CimInstanceSafe` | Consulta instâncias CIM com tratamento de erro seguro |

### 4.2. Funções do módulo `WbaToolkit.Networking`

| Função | Para que serve |
|---|---|
| `Get-NetworkContext` | Coleta contexto da rede local: IP, gateway, DNS e interface |
| `Test-GatewayConnectivity` | Testa comunicação com o gateway |
| `Test-DnsResolution` | Testa resolução DNS |
| `Test-IcmpConnectivity` | Testa ICMP, equivalente ao ping |
| `Test-TcpPortConnectivity` | Testa conexão TCP em uma porta |
| `Test-UdpPortConnectivity` | Testa envio UDP em uma porta |
| `Test-LocalTcpListener` | Verifica se uma porta TCP local está escutando |
| `Test-LocalUdpListener` | Verifica se existe endpoint UDP local |
| `New-ConnectivityTestPlan` | Cria plano padrão de teste de conectividade |
| `Invoke-ConnectivityTest` | Executa teste geral de conectividade com internet |
| `Invoke-ConnectivityWizard` | Abre wizard para teste geral de internet |
| `Invoke-TargetConnectivityTest` | Testa um alvo informado com protocolo e portas |
| `Invoke-TargetConnectivityWizard` | Wizard interativo para testar IP/nome, protocolo e portas |
| `Show-ConnectivityReport` | Mostra relatório de conectividade na tela |
| `Export-ConnectivityReport` | Gera relatório HTML |
| `Export-ConnectivityReportPdf` | Gera PDF quando suporte estiver disponível |

### 4.3. Funções do módulo `WbaToolkit.Startup`

| Função | Para que serve |
|---|---|
| `Get-StartupItem` | Retorna todos os itens de inicialização (Registro, pasta Startup, tarefas agendadas) |
| `Show-StartupItem` | Exibe a lista de itens de inicialização no console com estado ON/OFF |
| `Disable-StartupItem` | Desabilita um ou mais itens, preservando dados para reativação |
| `Enable-StartupItem` | Reativa itens previamente desabilitados pelo toolkit |
| `Remove-StartupItem` | Remove definitivamente um item da inicialização (com confirmação textual) |
| `Invoke-StartupManager` | Gerenciador interativo para seleção e modificação de entradas |
| `Get-ServiceStartupState` | Retorna o estado e tipo de inicialização de serviços do Windows |

### 4.4. Exemplo simples de uso de função do módulo

```powershell
Import-Module .\modules\WbaToolkit.Networking\WbaToolkit.Networking.psd1 -Force

$report = Invoke-TargetConnectivityTest `
    -TargetAddress 192.168.5.10 -Protocol TCP -PortSpec '80,443'
Show-ConnectivityReport -Report $report
```

## 5. Pasta padrão de relatórios

### 5.1. Como o toolkit escolhe o local

Os scripts devem gravar relatórios em uma sessão padronizada. A ordem de escolha é:

1. caminho informado no parâmetro do script, como `-DiretorioSaida` ou `-OutputDir`;
2. caminho salvo na configuração global do toolkit;
3. padrão `C:\WBA\Relatorios`, quando não houver configuração.

Dentro dessa raiz, cada script cria uma pasta do módulo e uma pasta da execução:

```text
C:\WBA\Relatorios\<Modulo>\<timestamp>\
```

Exemplos:

```text
C:\WBA\Relatorios\HD100\2026-06-10_153000\
C:\WBA\Relatorios\Inventory\2026-06-10_153000\
C:\WBA\Relatorios\Diagnostics\2026-06-10_153000\
C:\WBA\Relatorios\Maintenance\2026-06-10_153000\
C:\WBA\Relatorios\Updates\2026-06-10_153000\
```

### 5.2. Definir um local permanente

Use esta opção quando a equipe quiser que todos os relatórios sejam criados em outro disco, pasta técnica ou
compartilhamento de rede.

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
Set-ToolkitReportsRoot -Path "D:\Relatorios\WBA"
Get-ToolkitReportsRoot
```

A configuração fica gravada em:

```text
C:\ProgramData\WBA\WindowsToolkit\config.json
```

### 5.3. Usar outro local somente em uma execução

Quando quiser alterar apenas uma execução, use o parâmetro do próprio script:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 `
    -DiretorioSaida "D:\Atendimentos\Cliente01" -GerarHtml
```

Essa escolha não altera a configuração permanente.

## 6. Como gerar o portal de documentação HTML local

### 6.1. O que a função faz

A função `Export-ToolkitDocumentation` gera um portal HTML local completo com:

- portal do operador com acesso rápido ao MVP;
- guia do operador em HTML;
- referência técnica com CBH de todas as funções públicas;
- links entre funções relacionadas;
- documentação extraída dos comentários internos dos scripts e funções.

O resultado é um diretório local que pode ser aberto no navegador sem internet.

### 6.2. Quando usar

Use quando quiser consultar a documentação do toolkit em formato visual, com páginas HTML navegáveis.

Exemplos de uso:

- entregar documentação para um técnico;
- consultar funções disponíveis;
- abrir manual no navegador durante atendimento;
- gerar material local em computador sem internet.

### 6.3. Como gerar o portal padrão

Entre na raiz do projeto:

```powershell
Set-Location C:\ti\wba-windows-toolkit
```

Importe o módulo principal:

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
```

Gere o portal completo (portal operacional + referência técnica):

```powershell
Export-ToolkitDocumentation -Mode All -Force
```

Abra no navegador:

```powershell
Start-Process .\docs\portal\index.html
```

### 6.4. Onde ficam os arquivos

O portal é gerado em `.\docs\portal\` por padrão:

```text
docs\portal\
├── index.html          portal operacional com cards de ação
├── operador.html       guia do operador
└── referencia\
    └── index.html      referência técnica CBH
```

### 6.5. Como atualizar o portal

Sempre que novos scripts ou funções forem adicionados, gere novamente:

```powershell
Export-ToolkitDocumentation -Mode All -Force
```

O parâmetro `-Force` permite recriar o diretório mesmo que já exista.

### 6.6. Modos disponíveis

| Modo | O que gera |
|---|---|
| `All` | Portal operacional + referência técnica (padrão completo) |
| `Portal` | Somente o portal operacional e guia do operador |
| `TechnicalReference` | Somente a referência técnica CBH |

Exemplo com modo específico:

```powershell
Export-ToolkitDocumentation -Mode Portal -Force
```

### 6.7. Erros comuns

| Erro | Causa | Como resolver |
|---|---|---|
| Comando não reconhecido | Módulo não importado | Importe o `WbaToolkit.Core` (ver §3.1) |
| Diretório já existe | Falta `-Force` | Adicione `-Force` ao comando |
| Pasta errada gerada | PowerShell em diretório diferente | Execute `Set-Location C:\ti\wba-windows-toolkit` antes |
| HTML sem estilo | Arquivo errado aberto | Abra `index.html` na raiz de `docs\portal\` |

## 7. Script `Diagnostico-Reparo-HD100.ps1`

### 7.1. Finalidade

O script `Diagnostico-Reparo-HD100.ps1` ajuda a investigar o problema conhecido como “Disco 100%” ou “HD100”.

Ele coleta informações técnicas, gera relatórios e, no modo assistido, permite algumas ações controladas.

### 7.2. Quando usar

Use quando o computador apresentar:

- disco em 100% no Gerenciador de Tarefas;
- lentidão logo após ligar;
- travamentos ao abrir programas;
- demora excessiva após login;
- suspeita de problema em disco, serviços, atualização, antivírus ou programas na inicialização.

### 7.3. Quando não usar sem apoio técnico

Pare e chame alguém mais experiente se:

- o relatório indicar falha física ou lógica de disco;
- aparecer alerta de SMART;
- existirem eventos críticos de `Disk`, `Ntfs`, `storahci` ou `stornvme`;
- o computador contiver dados importantes sem backup;
- o equipamento estiver em produção crítica.

### 7.4. Execução recomendada

Entre na pasta do projeto:

```powershell
Set-Location C:\ti\wba-windows-toolkit
```

Execute em modo diagnóstico com HTML:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -GerarHtml
```

Esse modo é o mais seguro para começar. Ele gera relatório e não aplica correções permanentes.

### 7.5. Modos de execução

| Modo | O que faz | Indicação |
|---|---|---|
| `Diagnostico` | Coleta dados e gera relatório | Primeiro atendimento |
| `Assistido` | Coleta dados e oferece ações interativas | Técnico acompanhado ou operador treinado |
| `Relatorio` | Regera relatório usando execução anterior | Quando quiser recriar HTML |
| `Rollback` | Reativa entradas desabilitadas pelo HD100 | Para reverter desativação de teste |

### 7.6. Exemplos de uso

Diagnóstico seguro:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1
```

Diagnóstico com HTML:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -GerarHtml
```

Simulação sem executar comandos externos:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -DryRun -GerarHtml
```

Modo assistido:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -Modo Assistido -GerarHtml
```

Rollback de inicialização:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -Modo Rollback
```

### 7.7. O que ele coleta

O diagnóstico coleta:

- nome do computador;
- usuário;
- versão e build do Windows;
- memória;
- tempo ligado;
- tempo do último boot, quando disponível;
- uso médio do disco;
- fila média de disco;
- latência de leitura e escrita;
- processos com maior I/O;
- saúde do disco por `Get-PhysicalDisk`, `Get-Disk`, `Win32_DiskDrive` e SMART;
- eventos críticos de disco;
- volume de sistema e espaço livre;
- serviços relacionados a HD100;
- tarefas agendadas relacionadas;
- programas de inicialização;
- plugins bancários;
- antivírus;
- OneDrive;
- navegadores;
- Adobe Reader;
- drivers/controladores de armazenamento.

### 7.8. Relatórios gerados

Por padrão, os arquivos ficam em:

```text
C:\WBA\Relatorios\HD100\<data_hora>\
```

Arquivos principais:

| Arquivo | Uso |
|---|---|
| `relatorio-hd100.txt` | Relatório legível em texto |
| `relatorio-hd100.html` | Relatório visual para navegador, quando `-GerarHtml` for usado |
| `diagnostico.json` | Dados estruturados para análise técnica |
| `alteracoes.json` | Registro de alterações realizadas |
| `rollback.json` | Alterações reversíveis |
| `logs\chkdsk-scan.log` | Saída do CHKDSK `/scan` |
| `logs\dism.log` | Saída do DISM diagnóstico |
| `logs\eventos-disco.log` | Eventos relevantes de disco |

### 7.9. Como interpretar o relatório

Leia primeiro a seção `RESUMO`.

Pontos importantes:

| Campo | Como interpretar |
|---|---|
| `Status geral` | `NORMAL` ou `ATENCAO` |
| `Categoria provável` | Hipótese inicial do script |
| `Uso médio do disco` | Se estiver alto, indica pressão no disco |
| `Processo principal de I/O` | Processo que mais leu/escreveu dados |
| `Saúde do disco` | Se aparecer `Critico`, priorize backup |
| `Vida útil aproximada` | Estimativa baseada nos dados disponíveis |
| `Eventos críticos de disco` | Qualquer valor acima de zero merece atenção |
| `Inicialização ativa/inativa` | Quantidade de itens que iniciam com o Windows |
| `Tempo do último boot` | Tempo que o Windows registrou no último boot |

### 7.10. Programas na inicialização

O HD100 lista programas que iniciam com o Windows. No HTML eles aparecem com estado:

| Estado | Significado |
|---|---|
| `ON` | Inicia com o Windows |
| `OFF` | Está desabilitado |

Fontes analisadas:

- Registro `Run` e `RunOnce`;
- pasta Inicializar do usuário;
- pasta Inicializar global;
- tarefas agendadas com gatilho de logon ou boot.

No modo `Assistido`, o operador pode:

- desabilitar uma entrada para teste;
- habilitar novamente uma entrada desabilitada pelo HD100;
- remover definitivamente uma entrada da inicialização com confirmação textual.

Recomendação operacional:

> Desabilite uma entrada por vez, reinicie o computador e observe se o problema melhorou. Não remova definitivamente
> sem autorização ou sem saber a função do programa.

### 7.11. Ações sensíveis

Algumas ações exigem cuidado:

| Ação | Risco | Orientação |
|---|---|---|
| `CHKDSK /R` | Pode demorar horas e exigir reinicialização | Agende apenas com autorização |
| `SFC /scannow` | Pode reparar arquivos do sistema | Use em modo assistido |
| `DISM RestoreHealth` | Pode reparar imagem do Windows | Use em modo assistido |
| Remover inicialização | Pode impedir software necessário de iniciar | Prefira desabilitar antes |

## 8. Script `Inventario-Hardware-Software.ps1`

### 8.1. Finalidade

O script `Inventario-Hardware-Software.ps1` gera inventário técnico do computador. Ele pode criar o inventário
completo em HTML/PDF e também um resumo enxuto de hardware e drivers ativos.

### 8.2. Quando usar

Use quando precisar:

- documentar hardware e software instalado;
- comparar drivers antes e depois de uma intervenção;
- registrar versão de driver de vídeo, rede, áudio ou armazenamento;
- coletar evidência em casos de tela preta, DWM, travamento gráfico ou congelamento;
- fazer inventário rápido em campo.

### 8.3. Exemplos de uso

Inventário completo:

```powershell
.\experimental\inventory\Inventario-Hardware-Software.ps1
```

Inventário completo sem PDF:

```powershell
.\experimental\inventory\Inventario-Hardware-Software.ps1 -NaoPDF
```

Inventário completo e resumo de hardware/drivers:

```powershell
.\experimental\inventory\Inventario-Hardware-Software.ps1 -GerarResumoHardwareDrivers
```

Somente resumo rápido:

```powershell
.\experimental\inventory\Inventario-Hardware-Software.ps1 -SomenteHardwareDrivers
```

Somente Markdown:

```powershell
.\experimental\inventory\Inventario-Hardware-Software.ps1 `
    -SomenteHardwareDrivers -FormatoResumoHardwareDrivers Markdown
```

### 8.4. Relatórios gerados

Por padrão, os arquivos ficam em:

```text
C:\WBA\Relatorios\Inventory\<timestamp>\
```

Arquivos principais:

| Arquivo | Uso |
|---|---|
| `Inventario_*.html` | Inventário completo para navegador |
| `Inventario_*.pdf` | PDF opcional, quando houver navegador compatível |
| `resumo-hardware-drivers.txt` | Resumo legível em texto |
| `resumo-hardware-drivers.md` | Resumo para chamado, issue ou documentação |
| `resumo-hardware-drivers.json` | Dados estruturados para comparação automatizada |
| `logs\inventario-*.log` | Log da execução |

## 9. Script `Diagnostico-Driver-Grafico.ps1`

### 9.1. Finalidade

O script `Diagnostico-Driver-Grafico.ps1` coleta evidências para problemas de vídeo, tela preta, travamento gráfico,
falhas de DWM, TDR, WHEA, Kernel-Power e instabilidade relacionada a driver de GPU.

### 9.2. Quando usar

Use quando o computador apresentar:

- tela preta intermitente;
- congelamento ao abrir navegador, vídeo, Teams ou sistema gráfico;
- reinicialização após uso de GPU;
- erros de driver de vídeo no Visualizador de Eventos;
- suspeita de versão incorreta, antiga ou instável de driver gráfico.

### 9.3. Exemplos de uso

Diagnóstico seguro:

```powershell
.\experimental\diagnostics\Diagnostico-Driver-Grafico.ps1
```

Diagnóstico com HTML:

```powershell
.\experimental\diagnostics\Diagnostico-Driver-Grafico.ps1 -GerarHtml
```

Coleta assistida com HTML, DXDiag e EVTX:

```powershell
.\experimental\diagnostics\Diagnostico-Driver-Grafico.ps1 -Modo Assistido
```

### 9.4. Relatórios gerados

Por padrão, os arquivos ficam em:

```text
C:\WBA\Relatorios\Diagnostics\<timestamp>\
```

Arquivos principais:

| Arquivo | Uso |
|---|---|
| `relatorio-driver-grafico.txt` | Relatório legível em texto |
| `relatorio-driver-grafico.html` | Relatório visual, quando `-GerarHtml` for usado |
| `diagnostico-driver-grafico.json` | Dados estruturados |
| `logs\dxdiag.txt` | Saída opcional do DXDiag |
| `logs\System.evtx` | Exportação opcional do log System |
| `logs\Application.evtx` | Exportação opcional do log Application |

## 10. Script `Gerenciar-Inicializacao-Windows.ps1`

### 10.1. Finalidade

O script `Gerenciar-Inicializacao-Windows.ps1` é a ferramenta dedicada ao gerenciamento da inicialização do Windows.

Ele usa o módulo `WbaToolkit.Startup` para coletar, exibir e, no modo assistido, modificar entradas das três fontes:

- Registro (`Run` e `RunOnce` de HKLM e HKCU);
- pasta de inicialização do usuário e do sistema;
- tarefas agendadas com gatilho de logon ou boot.

Exibe também o estado e tipo de inicialização dos serviços mais relevantes.

> Use este script quando o objetivo for gerenciar exclusivamente a inicialização, sem executar o diagnóstico completo
> de disco 100% que o `Diagnostico-Reparo-HD100.ps1` realiza.

### 10.2. Quando usar

Use quando:

- o computador estiver lento no boot;
- o usuário reclamar de programas desnecessários ao ligar;
- precisar desabilitar serviços ou programas de inicialização para teste;
- precisar ver o que inicia com o Windows sem executar diagnóstico de disco;
- precisar reativar uma entrada desabilitada anteriormente pelo toolkit.

### 10.3. Modos de execução

| Modo | O que faz |
|---|---|
| `Diagnostico` | Apenas coleta e exibe informações, sem alterar nada (padrão) |
| `Assistido` | Permite desabilitar, reativar ou remover entradas de forma interativa |

### 10.4. Exemplos de uso

Diagnóstico somente leitura:

```powershell
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1
```

Diagnóstico com relatório HTML:

```powershell
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1 -GerarHtml
```

Modo assistido para modificações:

```powershell
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido
```

Simulação sem alterar o sistema:

```powershell
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido -DryRun
```

Em pasta de saída específica:

```powershell
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido -DiretorioSaida "D:\Atendimentos\Cliente01"
```

### 10.5. O que ele coleta e exibe

- todos os itens de inicialização agrupados por fonte e escopo;
- estado ON/OFF de cada entrada;
- lista numerada para seleção no modo assistido;
- estado e tipo de inicialização dos serviços principais.

### 10.6. Relatórios gerados

Os arquivos ficam em:

```text
C:\WBA\Relatorios\WbaToolkit.Startup\<timestamp>\
```

| Arquivo | Uso |
|---|---|
| `relatorio-inicializacao.txt` | Relatório em texto com itens, serviços e alterações |
| `relatorio-inicializacao.json` | Dados estruturados para análise ou auditoria |
| `alteracoes.json` | Registro de alterações quando houver modificações |
| `logs\inicializacao.log` | Log da sessão |

### 10.7. Segurança e reversibilidade

Todas as desativações são reversíveis. Antes de qualquer alteração, os dados originais são salvos em:

```text
HKLM:\SOFTWARE\WBA\WindowsToolkit\Startup\Disabled
```

Para reativar, use o mesmo script no modo assistido e escolha a opção `H` (Habilitar) na entrada desejada.

A remoção definitiva exige que o operador digite a frase `REMOVER INICIALIZACAO` para confirmar. Use com cuidado.

### 10.8. Uso via módulo diretamente

O módulo `WbaToolkit.Startup` pode ser usado independentemente do script:

```powershell
Import-Module .\modules\WbaToolkit.Startup\WbaToolkit.Startup.psd1 -Force

# Ver todos os itens
Get-StartupItem | Format-Table Name, SourceType, Enabled

# Ver apenas desabilitados
Get-StartupItem | Where-Object { -not $_.Enabled }

# Desabilitar pelo nome
$item = Get-StartupItem | Where-Object { $_.Name -eq 'OneDrive' }
Disable-StartupItem -Item $item

# Reativar
$item = Get-StartupItem | Where-Object { $_.ManagedDisabled -and $_.Name -eq 'OneDrive' }
Enable-StartupItem -Item $item
```

## 11. Script `Testar-Conectividade-Internet.ps1`

### 11.1. Finalidade

O script `Testar-Conectividade-Internet.ps1` executa um diagnóstico sequencial de conectividade com a internet. Ele
usa o módulo `WbaToolkit.Networking` para verificar rede local, gateway, DNS, ICMP e TCP.

### 11.2. Quando usar

Use quando houver:

- computador sem internet;
- DNS com comportamento instável;
- gateway inacessível;
- suspeita de bloqueio em firewall;
- necessidade de testar um destino, protocolo e portas específicas.

### 11.3. Diagnóstico geral de internet

```powershell
.\experimental\diagnostics\networking\Testar-Conectividade-Internet.ps1
```

Com detalhes:

```powershell
.\experimental\diagnostics\networking\Testar-Conectividade-Internet.ps1 -Detalhado
```

### 11.4. Teste direcionado por alvo

Para testar um IP, nome DNS, protocolo e portas específicas, importe o módulo de rede:

```powershell
Import-Module .\modules\WbaToolkit.Networking\WbaToolkit.Networking.psd1 -Force
Invoke-TargetConnectivityWizard
```

O wizard aceita `TCP`, `UDP`, `ICMP`, `Todos` ou lista separada por vírgula, como `TCP,UDP`.

Exemplo direto:

```powershell
$report = Invoke-TargetConnectivityTest -TargetAddress 192.168.5.10 -Protocol TCP -PortSpec '80,443,3389'
Show-ConnectivityReport -Report $report
```

## 12. Script `limpeza-windows.ps1`

### 12.1. Finalidade

O script `limpeza-windows.ps1` faz limpeza segura e manutenção conservadora do Windows.

Ele remove arquivos temporários, limpa caches, pode executar SFC/DISM, verificar eventos de disco e liberar espaço.

### 12.2. Quando usar

Use quando:

- o disco estiver com pouco espaço;
- houver muitos arquivos temporários;
- o computador estiver lento por acúmulo de resíduos;
- precisar limpar cache do Windows Update;
- precisar rodar SFC/DISM;
- precisar executar manutenção preventiva.

### 12.3. O que ele não remove

O script não remove:

- `C:\Windows\Installer`;
- WinSxS manualmente;
- drivers;
- perfis de usuários;
- programas instalados;
- documentos dos usuários;
- limpeza agressiva de registro.

### 12.4. Execução recomendada

```powershell
Set-Location C:\ti\wba-windows-toolkit
.\experimental\maintenance\limpeza-windows.ps1 -NoReboot
```

O parâmetro `-NoReboot` evita reinicialização automática.

### 12.5. Principais parâmetros

| Parâmetro | O que faz | Quando usar |
|---|---|---|
| `-Help` | Mostra ajuda | Quando tiver dúvida |
| `-Version` | Mostra versão | Conferência |
| `-NoReboot` | Não reinicia ao final | Padrão recomendado para atendimento |
| `-NoSfc` | Não executa SFC/DISM | Quando quiser só limpeza |
| `-RepararSistema` | Executa apenas SFC + DISM | Quando o objetivo for reparar Windows |
| `-NoUpdateCache` | Não limpa cache do Windows Update | Se houver atualização em andamento |
| `-NoRecycleBin` | Não esvazia lixeira | Se o usuário ainda precisa revisar arquivos |
| `-DisableHibernation` | Desativa hibernação | Para liberar espaço do `hiberfil.sys` |
| `-SetPageFile` | Configura pagefile fixo | Apenas com orientação técnica |
| `-PageFileGB` | Define tamanho do pagefile | Usado junto com `-SetPageFile` |
| `-EnableCompactOS` | Ativa CompactOS | Em máquinas com pouco disco |
| `-NoOptimizeVolume` | Não otimiza volume | Se quiser evitar otimização de disco |
| `-ChkdskAction` | `Schedule` ou `Skip` | Define se agenda CHKDSK |
| `-EventLogCleanup` | `All`, `ErrorOnly` ou `None` | Define limpeza do Visualizador de Eventos |

### 12.6. Exemplos seguros

Limpeza sem reiniciar:

```powershell
.\experimental\maintenance\limpeza-windows.ps1 -NoReboot
```

Somente reparar sistema:

```powershell
.\experimental\maintenance\limpeza-windows.ps1 -RepararSistema -NoReboot
```

Limpeza sem SFC/DISM:

```powershell
.\experimental\maintenance\limpeza-windows.ps1 -NoSfc -NoReboot
```

Automação conservadora:

```powershell
.\experimental\maintenance\limpeza-windows.ps1 -ChkdskAction Skip -EventLogCleanup None -NoReboot
```

### 12.7. Onde fica o log

O script cria log em:

```text
C:\WBA\Relatorios\Maintenance\<timestamp>\logs
```

O nome costuma seguir o formato:

```text
yyyy-MM-dd_HHmmss-limpeza-windows.log
```

### 12.8. Cuidados operacionais

- Use `-NoReboot` se o usuário estiver trabalhando.
- Não use `-EventLogCleanup All` sem autorização.
- Não use `-SetPageFile` sem orientação técnica.
- Não use `-DisableHibernation` se o usuário depende de hibernação.
- Antes de `ChkdskAction Schedule`, avise que pode haver verificação no próximo boot.

## 13. Script `upgrade-windows.ps1`

### 13.1. Finalidade

O script `upgrade-windows.ps1` aciona uma rotina simples e conservadora de atualização.

Ele tenta:

- acionar o Windows Update nativo com `UsoClient.exe`;
- atualizar o Chocolatey, se existir;
- atualizar pacotes instalados via Chocolatey.

Ele não instala Chocolatey, não instala WinGet e não força reinicialização.

### 13.2. Quando usar

Use quando:

- precisar iniciar busca de atualizações do Windows;
- precisar atualizar pacotes gerenciados pelo Chocolatey;
- precisar executar uma rotina básica de atualização sem módulos adicionais.

### 13.3. Execução recomendada

```powershell
Set-Location C:\ti\wba-windows-toolkit
.\experimental\updates\upgrade-windows.ps1 -PauseAtEnd
```

O parâmetro `-PauseAtEnd` mantém a janela aberta no final, útil para copiar mensagens e conferir o resultado.

### 13.4. Principais parâmetros

| Parâmetro | O que faz |
|---|---|
| `-Help` | Mostra ajuda |
| `-Version` | Mostra versão |
| `-NoWindowsUpdate` | Não aciona Windows Update |
| `-NoChocolatey` | Não atualiza Chocolatey |
| `-NoRebootWarning` | Não exibe aviso de reinicialização |
| `-PauseAtEnd` | Aguarda ENTER antes de fechar |

### 13.5. Exemplos

Executar atualização completa:

```powershell
.\experimental\updates\upgrade-windows.ps1
```

Somente Chocolatey:

```powershell
.\experimental\updates\upgrade-windows.ps1 -NoWindowsUpdate
```

Somente Windows Update:

```powershell
.\experimental\updates\upgrade-windows.ps1 -NoChocolatey
```

Manter janela aberta:

```powershell
.\experimental\updates\upgrade-windows.ps1 -PauseAtEnd
```

### 13.6. Onde fica o log

O log fica em:

```text
C:\WBA\Relatorios\Updates\<timestamp>\logs
```

Nome esperado:

```text
yyyy-MM-dd_HHmmss-upgrade-windows.log
```

### 13.7. Como acompanhar o Windows Update

O `UsoClient.exe` normalmente não mostra progresso detalhado no console.

Depois de rodar o script, confira manualmente:

```text
Configurações > Atualização e Segurança > Windows Update
```

Em Windows 11:

```text
Configurações > Windows Update
```

### 13.8. Cuidados

- Atualizações podem exigir reinicialização.
- Chocolatey depende da internet e do repositório configurado.
- Se Chocolatey falhar por timeout, tente novamente mais tarde.
- Não desligue o computador durante instalação de atualização.

## 14. Script `Preparar-Imagem-Windows.ps1`

### 14.1. Finalidade

O script `Preparar-Imagem-Windows.ps1` aplica tweaks no perfil Default do Windows e,
opcionalmente, inicia o sysprep para preparar uma imagem corporativa.

### 14.2. Quando usar

Use quando precisar:

- criar uma imagem padronizada para distribuição em lote;
- aplicar configurações ao perfil Default antes de capturar imagem;
- validar o efeito dos tweaks antes de acionar o sysprep.

### 14.3. Modos de execução

| Parâmetro | O que faz |
|---|---|
| `-ApenasDryRun` | Simula tweaks sem alterar o sistema (obrigatório antes da primeira execução) |
| `-SemSysprep` | Aplica tweaks no perfil Default mas não inicia o sysprep |
| (nenhum) | Aplica tweaks e inicia o sysprep |

### 14.4. Exemplos de uso

Simulação obrigatória antes da primeira execução:

```powershell
.\experimental\maintenance\Preparar-Imagem-Windows.ps1 -ApenasDryRun
```

Apenas aplicar tweaks, sem sysprep:

```powershell
.\experimental\maintenance\Preparar-Imagem-Windows.ps1 -SemSysprep
```

Execução completa (tweaks + sysprep):

```powershell
.\experimental\maintenance\Preparar-Imagem-Windows.ps1
```

---

## 15. Script `Configurar-Idioma-Regional.ps1`

### 15.1. Finalidade

O script `Configurar-Idioma-Regional.ps1` padroniza idioma, locale regional e fuso horário
de instalações Windows 10/11 para o padrão brasileiro (pt-BR).

### 15.2. Quando usar

Use quando precisar:

- padronizar o idioma em uma nova instalação;
- corrigir locale regional em máquina com configuração incorreta;
- implantar configuração de idioma via automação (GPO, SCCM);
- ajustar fuso horário para uma região específica.

### 15.3. Principais parâmetros

| Parâmetro | O que faz |
|---|---|
| `-Silent` | Sem interação; para automação |
| `-NoReboot` | Não reinicia ao final |
| `-TimeZone` | Define fuso (padrão: UTC-4) |
| `-ListTimeZones` | Lista fusos disponíveis |

### 15.4. Exemplos de uso

Configuração padrão (pt-BR, UTC-4):

```powershell
.\configuration\Configurar-Idioma-Regional.ps1
```

Modo silencioso sem reboot (automação):

```powershell
.\configuration\Configurar-Idioma-Regional.ps1 -Silent -NoReboot
```

Fuso de Brasília (UTC-3):

```powershell
.\configuration\Configurar-Idioma-Regional.ps1 -TimeZone "E. South America Standard Time"
```

Listar fusos do Brasil:

```powershell
.\configuration\Configurar-Idioma-Regional.ps1 -ListTimeZones
```

---

## 16. Script `Analise-Espaco-Disco.ps1`

### 16.1. Finalidade

O script `Analise-Espaco-Disco.ps1` varre os volumes locais, identifica as 20 maiores pastas
e os 10 maiores arquivos e estima categorias de espaço desperdiçado. Gera relatório HTML.

### 16.2. Quando usar

Use quando precisar:

- identificar o que ocupa mais espaço no disco;
- detectar categorias de limpeza (temp, cache, dumps, Windows.old);
- gerar evidência antes de uma limpeza manual;
- documentar uso de disco por pasta.

### 16.3. Exemplos de uso

Varrer todos os volumes locais:

```powershell
.\utilities\Analise-Espaco-Disco.ps1
```

Varrer somente o volume C:

```powershell
.\utilities\Analise-Espaco-Disco.ps1 -Drive C
```

Sem conversão para PDF:

```powershell
.\utilities\Analise-Espaco-Disco.ps1 -NaoPDF
```

Salvar em pasta específica:

```powershell
.\utilities\Analise-Espaco-Disco.ps1 -OutputDir "D:\Relatorios"
```

---

## 17. Script `Remover-Perfis-Inativos.ps1`

### 17.1. Finalidade

O script `Remover-Perfis-Inativos.ps1` lista perfis de usuário locais com espaço em disco
e permite remover interativamente perfis antigos, inativos ou órfãos.

### 17.2. Quando usar

Use quando precisar:

- recuperar espaço de perfis de usuários que não usam mais o computador;
- remover perfis órfãos (conta do domínio excluída);
- limpar máquina compartilhada com perfis acumulados;
- verificar quais perfis existem e quanto ocupam.

### 17.3. Principais parâmetros

| Parâmetro | O que faz |
|---|---|
| `-DryRun` | Lista o que seria removido sem alterar nada |
| `-Silent` | Remove órfãos e inativos sem confirmação manual |
| `-ExcludeProfile` | Lista de perfis a preservar |

### 17.4. Exemplos de uso

Simulação — ver o que seria removido:

```powershell
.\utilities\Remover-Perfis-Inativos.ps1 -DryRun
```

Modo interativo (padrão):

```powershell
.\utilities\Remover-Perfis-Inativos.ps1
```

Automático sem interação:

```powershell
.\utilities\Remover-Perfis-Inativos.ps1 -Silent
```

Excluindo perfis específicos:

```powershell
.\utilities\Remover-Perfis-Inativos.ps1 -ExcludeProfile "svc.backup","adm.temp"
```

---

## 18. Script `Diagnostico-GPO-Client.ps1`

### 18.1. Finalidade

O script `Diagnostico-GPO-Client.ps1` diagnostica falhas de aplicação de GPO em clientes
Windows, verificando canal seguro, conectividade com DC, SYSVOL, GPOs aplicadas e eventos.

### 18.2. Quando usar

Use quando:

- o usuário reclamar que políticas de grupo não estão sendo aplicadas;
- `gpupdate /force` falhar ou não surtir efeito;
- houver erros de canal seguro ou autenticação no domínio;
- a máquina aparecer como fora do domínio.

### 18.3. Principais parâmetros

| Parâmetro | O que faz |
|---|---|
| `-DomainFQDN` | FQDN do domínio (detecção automática se omitido) |
| `-DCName` | DC preferencial (detecção automática se omitido) |
| `-SkipReparo` | Somente diagnóstico; sem oferecer reparos |

### 18.4. Exemplos de uso

Diagnóstico com detecção automática:

```powershell
.\active-directory\Diagnostico-GPO-Client.ps1
```

Somente leitura com DC específico:

```powershell
.\active-directory\Diagnostico-GPO-Client.ps1 -DCName DC01 -SkipReparo
```

Com FQDN do domínio informado:

```powershell
.\active-directory\Diagnostico-GPO-Client.ps1 -DomainFQDN contoso.local
```

---

## 19. Script `Testa-Repara-ContaMaquinaAD.ps1`

### 19.1. Finalidade

O script `Testa-Repara-ContaMaquinaAD.ps1` executa sequência interativa de testes para validar
e reparar a conta de máquina e o canal seguro no domínio Active Directory.

### 19.2. Quando usar

Use quando:

- a máquina não conseguir autenticar no domínio;
- o canal seguro estiver quebrado (`Test-ComputerSecureChannel` retorna `$false`);
- tickets Kerberos da conta de computador falharem;
- `net ads testjoin` indicar falha.

### 19.3. Principais parâmetros

| Parâmetro | O que faz |
|---|---|
| `-DomainFqdn` | FQDN do domínio (detecção automática se omitido) |
| `-DomainNetBIOS` | NetBIOS do domínio |
| `-PreferredDc` | IP ou nome do DC preferencial |
| `-DnsServers` | Lista de DNS a usar nos testes |

### 19.4. Exemplos de uso

Diagnóstico com detecção automática:

```powershell
.\active-directory\Testa-Repara-ContaMaquinaAD.ps1
```

Com domínio e DC específicos:

```powershell
.\active-directory\Testa-Repara-ContaMaquinaAD.ps1 `
    -DomainFqdn contoso.local -PreferredDc DC01
```

Com DNS específico:

```powershell
.\active-directory\Testa-Repara-ContaMaquinaAD.ps1 `
    -DomainFqdn contoso.local -DnsServers 192.168.1.7
```

---

## 20. Fluxo de atendimento recomendado

### 20.1. Quando o problema é disco 100%

1. Abrir PowerShell como Administrador.
2. Entrar na pasta do toolkit.
3. Executar:

```powershell
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -GerarHtml
```

4. Abrir o HTML gerado.
5. Verificar:
   - saúde do disco;
   - eventos críticos;
   - uso médio do disco;
   - processo principal de I/O;
   - programas na inicialização.
6. Se o disco estiver saudável, considerar modo assistido.
7. Desabilitar apenas uma entrada de inicialização por vez.
8. Reiniciar e testar.

### 20.2. Quando o problema é pouco espaço em disco

1. Executar:

```powershell
.\experimental\maintenance\limpeza-windows.ps1 -NoReboot
```

2. Verificar o log em `C:\WBA\Relatorios\Maintenance\<timestamp>\logs`.
3. Confirmar espaço livre depois da execução.

### 20.3. Quando o problema é sistema desatualizado

1. Executar:

```powershell
.\experimental\updates\upgrade-windows.ps1 -PauseAtEnd
```

2. Conferir Windows Update nas Configurações.
3. Reiniciar se o Windows solicitar.

### 20.4. Quando o problema é tela preta ou travamento gráfico

1. Executar:

```powershell
.\experimental\diagnostics\Diagnostico-Driver-Grafico.ps1 -Modo Assistido
```

2. Abrir o HTML gerado.
3. Verificar:
   - GPU detectada;
   - versão e data do driver;
   - eventos `Display`, `DWM`, `DirectX`, `WHEA`, `BugCheck` e `Kernel-Power`;
   - processos com aceleração gráfica;
   - plano de energia e inicialização rápida.
4. Se for trocar driver, gerar também:

```powershell
.\experimental\inventory\Inventario-Hardware-Software.ps1 -SomenteHardwareDrivers
```

5. Depois da intervenção, executar o resumo novamente e comparar a versão do driver.

### 20.5. Quando precisa de portal de documentação local

1. Importar módulo:

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
```

2. Gerar portal:

```powershell
Export-ToolkitDocumentation -Mode All -Force
```

3. Abrir:

```powershell
Start-Process .\docs\portal\index.html
```

## 21. Mensagens comuns e o que fazer

| Situação | Causa | Ação |
|---|---|---|
| Script bloqueado por política | Windows bloqueou execução | `Set-ExecutionPolicy Bypass -Scope Process -Force` |
| Precisa de administrador | Script exige elevação | Abrir PowerShell como Administrador |
| Chocolatey não encontrado | Não instalado no computador | A etapa é ignorada automaticamente |
| UsoClient sem progresso visível | Comportamento normal do Windows | Verificar em Configurações > Windows Update |
| DISM ou SFC demora muito | Normal em alguns computadores | Aguardar; não interromper |
| CHKDSK agendado no próximo boot | Verificação agendada | Avisar o usuário antes de reiniciar |
| Relatório HTML não abre | Caminho incorreto | Abrir `index.html` ou `relatorio-hd100.html` na pasta correta |

## 22. Regras de segurança para operador

1. Comece sempre pelo modo diagnóstico.
2. Leia o resumo antes de executar correções.
3. Se houver alerta de disco, priorize backup.
4. Não remova programas de inicialização sem autorização.
5. Desabilite uma entrada por vez e documente o teste.
6. Não limpe todos os eventos do Visualizador sem necessidade.
7. Não altere pagefile sem orientação.
8. Não interrompa SFC, DISM, CHKDSK ou atualização em andamento.
9. Guarde o caminho do relatório e do log.
10. Em dúvida, pare e escale para um técnico mais experiente.

## 23. Checklist rápido

Antes de executar:

- [ ] Estou no PowerShell como Administrador.
- [ ] Estou na pasta `C:\ti\wba-windows-toolkit`.
- [ ] Rodei `Set-ExecutionPolicy Bypass -Scope Process -Force` se necessário.
- [ ] Sei qual script vou executar.
- [ ] Avisei o usuário sobre possível demora.

Depois de executar:

- [ ] Anotei onde está o log.
- [ ] Anotei onde está o relatório.
- [ ] Verifiquei se houve erro.
- [ ] Se alterei inicialização, registrei o que foi alterado.
- [ ] Se o script pediu reinicialização, avisei o usuário.
