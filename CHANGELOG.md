# Changelog

## [Não lançado]

### Adicionado
- `updates/upgrade-windows.ps1`: reescrito com suporte a backend resolvido (Auto, WinGet, Chocolatey, All), ações UpgradeAll/ListOnly/Select, bloqueios `-NoWinGet`/`-NoChocolatey`/`-NoWindowsUpdate`, detecção de reboot pendente antes e após execução, resumo final consolidado e códigos de saída padronizados (BCK-018)
- `tests/unit/upgrade-windows.Tests.ps1`: suite Pester com 62 testes cobrindo validação de parâmetros, resolução de backend, detecção de reboot, cálculo de código de saída e todos os fluxos de ação (BCK-018)
- `tools/release-check.sh`: pré-voo de release anti-LFS para validar arquivos rastreados por Git LFS e bloquear ponteiros antes da tag/publicação
- `xtudo.ps1`: launcher único do toolkit com atalhos rápidos e busca por palavra-chave para scripts operacionais

### Alterado
- `scripts/`: promoção do MVP para camada oficial do operador com `limpar-windows.ps1`, `limpar-winsxs.ps1`, `diagnosticar-disco-100.ps1`, `diagnosticar-memoria.ps1`, `diagnosticar-grafico.ps1`, `preparar-imagem-windows.ps1`, `testar-conectividade-internet.ps1`, `verificar-atualizacoes-hardware.ps1` e `atualizar-windows.ps1`
- `manuais/` e `tests/`: caminhos e expectativas atualizados para o estado atual do MVP, com validação Pester 24/24 verde
- `tools/publish-release.sh`: agora executa `tools/release-check.sh` antes de criar tags e publicar releases
- `README.md`: rito de release documentado com o pré-voo anti-LFS

## [v1.3.0] — 2026-06-20

### Adicionado
- `tests/lab-ad/`: scripts de provisionamento de laboratório de Active Directory (DC + cliente membro) e runbook para validar `Diagnostico-GPO-Client.ps1` e `Testa-Repara-ContaMaquinaAD.ps1`, que exigem um domínio real (validação operacional PS 5.1/7.6.2)

### Corrigido
- `modules/WbaToolkit.Core/Public/Invoke-Safe.ps1`: verificação de exit code era código morto (`$LASTEXITCODE` local mascarava o global); agora detecta falha de comando nativo (DEV-019)
- `modules/WbaToolkit.Maintenance/Public/Remove-SafePath.ps1`: adicionada whitelist de raízes (`-AllowedRoot`), canonicalização anti path traversal, recusa de raízes/diretórios críticos e `SupportsShouldProcess` (-WhatIf) (DEV-019)
- `modules/WbaToolkit.Startup`: ciclo Disable→store→Enable preserva o tipo nativo do registro (REG_EXPAND_SZ/REG_BINARY/REG_DWORD) via `RegistryValueKind`+valor bruto; `Enable-StartupItem` não recria mais a chave Run existente (não apaga outros valores); `SupportsShouldProcess`/-WhatIf real em Disable/Enable/Remove; `Get-ManagedDisabledStartupItems` robustecida (DEV-019)
- `active-directory/Diagnostico-GPO-Client.ps1`: regex super-escapado tornava a detecção de canal seguro código morto; corrigido para `NERR_Success|0x0` (DEV-019)
- `maintenance/Diagnostico-Reparo-HD100.ps1`: `-Modo Rollback` chamava função inexistente; relatório HTML referenciava propriedades de sessão inexistentes (DEV-019)
- `active-directory/Testa-Repara-ContaMaquinaAD.ps1` e `utilities/Analise-Espaco-Disco.ps1`: corrigido erro de parse `[CmdletBinding()]` sem `param()` (16 funções) que impedia o carregamento dos scripts — estes ainda falhavam no parse na v1.2.0 (DEV-019)
- `maintenance/limpeza-windows.ps1` e `modules/WbaToolkit.Maintenance/Public/Invoke-ComponentStoreCleanup.ps1`: corrigida regressão da refatoração BCK-003 — prompt de confirmação do DISM oculto atrás da barra de progresso e ausência de feedback; removido `Write-Progress` que cobria prompts, DISM em nível Standard sem prompt (`-Confirm:$false`), saída do DISM exibida em tempo real e resultado informado (DEV-020)
- `maintenance/limpeza-windows.ps1`: `Start-Transcript` sem `-Encoding` (parâmetro inexistente no PS 5.1 e variável entre versões do PS 7) para o log de transcrição funcionar (DEV-020)
- `modules/WbaToolkit.Networking/Public/Test-IcmpConnectivity.ps1` e `active-directory/Diagnostico-GPO-Client.ps1`: latência média do ping zerava no PowerShell 7 — `Test-Connection` expõe `Latency` no PS 7+ e `ResponseTime` no PS 5.1; passa a selecionar a propriedade existente em runtime, mantendo compatibilidade com ambas as versões (validação operacional)
- `maintenance/Diagnostico-Reparo-HD100.ps1`: o wrapper `Initialize-HD100Session` marcava `-BasePath` como obrigatório e rejeitava o `-Path`/`-DiretorioSaida` vazio (padrão) quando omitido; `BasePath` tornado opcional, alinhando ao contrato de `Initialize-ScriptSession` (validação operacional)
- `utilities/Analise-Espaco-Disco.ps1`: totalizadores de volume (Total/Livre/Usado/Ocupação) saíam zerados — `System.IO.DriveInfo` não possui `.Size`/`.FreeSpace`; corrigido para `TotalSize`/`TotalFreeSpace` (validação operacional)
- `inventory/Inventario-Hardware-Software.ps1`: desreferência de objetos CIM nulos (ex.: `Win32_BaseBoard` em VMs) lançava `PropertyNotFoundException` sob `Set-StrictMode 2.0` na geração do HTML; campos de placa-mãe, BIOS, computador e SO resolvidos com guarda (validação operacional)

### Alterado
- Aplicado UTF-8 com BOM a todos os `.ps1`/`.psm1`/`.psd1` que estavam sem BOM, em conformidade com o ADR 0007 (DEV-020)
- `tests/unit/WbaToolkit.Maintenance.Tests.ps1`: testes de `Remove-SafePath` atualizados para o novo contrato de whitelist e adicionado teste de recusa fora das raízes permitidas
- `utilities/Analise-Espaco-Disco.ps1` e `inventory/Inventario-Hardware-Software.ps1`: parâmetro padronizado para `-Path` com `[Alias('DiretorioSaida')]`, substituindo `-OutputDir` e alinhando aos demais scripts
- `tests/unit/WbaToolkit.Core.Tests.ps1`: assertivas de `Format-FileSize` tornadas independentes de cultura (o separador decimal de cultura é comportamento esperado, não defeito — ver `spec/IMPLEMENTADO.md`); validam unidade, valor e precisão

## [v1.2.0] — 2026-06-18

### Adicionado
- `diagnostics/Diagnostico-Memoria.ps1`: top-N consumidores de memória RAM com métricas de memória paginada, física e virtual; `-Todos` lista todos os processos
- `diagnostics/Verificar-Atualizacoes-Hardware.ps1`: diagnóstico somente leitura de BIOS (versão, data, ferramenta oficial do fabricante) e drivers (inventário Win32_PnPSignedDriver, assinatura, idade) com busca de drivers pendentes via Windows Update COM API
- `maintenance/Backup-Restaurar-Drivers.ps1`: backup e restauração de drivers não-Windows via DISM/pnputil; modos Backup e Restore; suporte a `-DryRun` e `-GerarHtml`
- `maintenance/Limpeza-WinSxS.ps1`: script operacional com modos Diagnostico, Limpeza e Relatorio para gestão assistida do Component Store (BCK-002)
- `modules/WbaToolkit.Maintenance/Public/Remove-SafePath.ps1`: remove arquivos de um diretório com filtro opcional por idade (BCK-003)
- `modules/WbaToolkit.Maintenance/Public/Get-DiskInfo.ps1`: retorna tamanho e espaço livre do SystemDrive via WMI (BCK-003)
- `modules/WbaToolkit.Maintenance/Public/Get-FilesystemErrorEvent.ps1`: consulta eventos de erro/falha no log System (BCK-003; renomeada de Get-FilesystemErrorEvents para forma singular)
- `modules/WbaToolkit.Maintenance/Public/Write-MaintenanceEvent.ps1`: registra evento no Visualizador de Eventos com fonte parametrizada (BCK-003; substitui Write-ScriptEvent local)
- `modules/WbaToolkit.Maintenance/Public/Invoke-FilesystemCheck.ps1`: verifica eventos de falha no sistema de arquivos e oferece agendamento de chkdsk (BCK-003; CallerScript e EventSource parametrizados)
- `modules/WbaToolkit.Maintenance/Public/Invoke-EventLogMaintenance.ps1`: limpa logs do Visualizador de Eventos com backup opcional de erros (BCK-003; substitui Invoke-EventLogCleanup local)
- `modules/WbaToolkit.Maintenance/Private/Register-MaintenanceEventSource.ps1`: registra fonte de eventos no Visualizador; Source parametrizado (BCK-003)
- `modules/WbaToolkit.Maintenance/Private/ConvertTo-StoreSizeGB.ps1`: converte valor e unidade DISM para GB (BCK-002; auxiliar interno)
- `modules/WbaToolkit.Maintenance/Public/Get-ComponentStoreInfo.ps1`: analisa Component Store via DISM AnalyzeComponentStore; operação somente leitura (BCK-002)
- `modules/WbaToolkit.Maintenance/Public/Invoke-ComponentStoreCleanup.ps1`: executa limpeza do WinSxS via DISM com suporte a DryRun, WhatIf e nível Aggressive/ResetBase (BCK-002)

### Alterado
- Todos os módulos alinhados para versão 1.2.0: `WbaToolkit.Core`, `WbaToolkit.Networking`, `WbaToolkit.Startup`, `WbaToolkit.Maintenance`
- `modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psd1`: versão 1.1.0 → 1.2.0; 8 novas funções exportadas (BCK-002 + BCK-003)
- `modules/WbaToolkit.Maintenance/WbaToolkit.Maintenance.psm1`: Export-ModuleMember atualizado com 8 novas funções
- `maintenance/limpeza-windows.ps1`: 7 funções internas extraídas para WbaToolkit.Maintenance; substitui chamadas DISM inline por Invoke-ComponentStoreCleanup (BCK-003 + BCK-002)
- `tests/unit/WbaToolkit.Maintenance.Tests.ps1`: testes de exportação e comportamento para as 8 novas funções públicas
- `diagnostics/Diagnostico-Memoria.ps1`: parâmetro padronizado para `-Path` com `[Alias('DiretorioSaida')]`; `[CmdletBinding()]` adicionado; métrica Mem. Virtual substituída por Mem. Paginada

### Corrigido
- `modules/WbaToolkit.Maintenance/Public/Invoke-EventLogMaintenance.ps1`: `[List[string]]::new()` e hashtable inline com backtick causavam "Token '}' inesperado" no PS 5.1; substituídos por `@()` e variável `$filter`
- 10 arquivos: `[System.Collections.Generic.List[T]]::new()` e `[Stack[T]]::new()` com tipos genéricos aninhados causavam ParserError no PS 5.1; substituídos por `New-Object 'tipo[param]'` (24 ocorrências)
- 6 scripts operacionais sem bloco de identificação `$ScriptName`/`$ScriptPath`/`$ScriptDir` (ADR 0006): `Diagnostico-GPO-Client.ps1`, `Inventario-Hardware-Software.ps1`, `Backup-Restaurar-Drivers.ps1`, `Gerenciar-Inicializacao-Windows.ps1`, `Preparar-Imagem-Windows.ps1`, `Testar-Conectividade-Internet.ps1`
- 45 arquivos `.ps1`: UTF-8 BOM restaurado conforme ADR 0007
- `diagnostics/Diagnostico-Memoria.ps1`: variável reservada `$pid` renomeada para `$processId`
- Vários scripts: `[CmdletBinding()]` e tipos de parâmetros ausentes adicionados; parâmetro `-DiretorioSaida` padronizado para `-Path` com alias (ADR 10.3)

## [v1.1.4] — 2026-06-14

### Adicionado
- `tools/build-pdf.sh`: pipeline de geração de PDF via Pandoc + LuaLaTeX em dois passos (pandoc → .tex, latexmk → PDF); validação de acentuação escapada; documentação de dependências TeX Live
- `docs/latex/preambulo.tex`: preâmbulo LaTeX alinhado ao ADR 0019; quebra automática de linhas em blocos de código (`fvextra`); margens A4; cabeçalho/rodapé; tabelas com wrap
- `docs/latex/pandoc-defaults.yaml`: configuração do pipeline Pandoc (LuaLaTeX, sumário, highlight tango)
- `docs/latex/build/.gitkeep`: diretório de build LaTeX rastreado no git

### Alterado
- `docs/manual-operador-wba-windows-toolkit.md`: alinhado com v1.1.3; 6 novas seções para scripts ausentes (Preparar-Imagem, Configurar-Idioma, Analise-Espaco, Remover-Perfis, Diagnostico-GPO, Testa-Repara-ContaMaquinaAD); parâmetros corrigidos; tabelas largas corrigidas; linhas longas de código quebradas com continuação PS5
- `docs/manual/operador/guia-rapido.md`: todos os 13 scripts documentados com parâmetros corretos
- `docs/manual-operador-wba-windows-toolkit.pdf`: regenerado com pipeline LaTeX; margens respeitadas; blocos de código com quebra automática; tabelas sem overflow

### Removido
- `docs/latex/header-includes.tex`: substituído por `preambulo.tex` (renomeação para nome canônico da spec)

## [v1.1.3] — 2026-06-14

### Alterado
- `RELEASE-NOTES.md` atualizado para v1.1.3 com janela deslizante correta (v1.1.3 → v1.1.2 → v1.1.1)

## [v1.1.2] — 2026-06-14

### Adicionado
- `RELEASE-NOTES.md`: documento de apresentação da release (módulos, scripts, início rápido) publicado como corpo da release no Codeberg
- `tools/publish-codeberg-release.sh`: script bash para publicar release no Codeberg via API com `RELEASE-NOTES.md` como corpo

## [v1.1.1] — 2026-06-14

### Alterado
- `docs/manual/README.md`: `Export-ToolkitDocumentation` adicionado na referência técnica; contagem de funções do Core corrigida (23→24); exemplo de geração atualizado
- `docs/manual/referencia/modulos.md`: `Export-ToolkitDocumentation` adicionado na tabela de utilitários do Core; cabeçalho atualizado
- `docs/manual/operador/guia-rapido.md`: seção de geração de portal HTML adicionada

## [v1.1.0] — 2026-06-14

### Adicionado
- `Export-ToolkitDocumentation` — comando unificado de portal HTML (ADR 0013); gera `index.html`, `operador.html` e referência técnica via `Export-ToolkitFunctionDocs`; suporta `-Mode All|Portal|TechnicalReference` e `-IncludeChangelog`
- `ConvertFrom-MarkdownSimple` (privada) — conversor Markdown→HTML em PS 5.1 puro (máquina de estados: headings, tabelas, listas, fenced code)
- `New-PortalIndexHtml` (privada) — gerador de portal index.html com cards de ação e catálogo convertido de `docs/manual/README.md`

## [v1.0.1] — 2026-06-14

### Adicionado
- Estrutura `docs/manual/` com catálogo geral de scripts por função operacional, guia rápido do operador e referência de módulos e funções públicas

## [v1.0.0] — 2026-06-14

### Adicionado
- Módulo WbaToolkit.Startup: lista, habilita, desabilita e remove itens de inicialização do Windows (registro, pasta de inicialização e tarefas agendadas)
- Módulo WbaToolkit.Maintenance: prepara imagem corporativa para sysprep com dry-run obrigatório, backup de NTUSER.DAT e confirmação explícita do operador
- Script Gerenciar-Inicializacao-Windows.ps1: interface assistida para gerenciamento de itens de inicialização
- Script Preparar-Imagem-Windows.ps1: aplica tweaks ao perfil Default antes do sysprep, com suporte a `-ApenasDryRun` e `-SemSysprep`
- Funções WbaToolkit.Core: Read-UserInput, Write-ScriptLog, Initialize-ScriptSession, Get-CimInstanceSafe, Write-TextFileUtf8, Get-Utf8BomEncoding, Get-ToolkitConfiguration
- Exportação de resumo de drivers de hardware em inventário
- Assistente de conectividade com suporte a múltiplos protocolos por destino
- Diagnóstico de driver gráfico com relatório TXT

### Corrigido
- Criação da sessão de relatório padrão adiada para evitar diretórios vazios em execuções sem saída

### Alterado
- Scripts HD100, Gráficos e AD refatorados para usar funções compartilhadas do WbaToolkit.Core
- Sessões de saída de relatório padronizadas em todos os scripts de diagnóstico
- Todos os módulos atualizados para ModuleVersion 1.0.0

## [v0.1.0] — 2026-05-01

### Adicionado
- Módulo WbaToolkit.Core com funções utilitárias compartilhadas
- Módulo WbaToolkit.Networking com testes de conectividade TCP/UDP/ICMP/DNS
- Script Diagnostico-Reparo-HD100.ps1 com diagnóstico de disco e relatório HTML
