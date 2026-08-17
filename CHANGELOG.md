# Changelog

## [Não lançado]

### Adicionado
- `scripts/diagnosticar-dropbox.ps1` e `scripts/auditar-arquivos-dropbox.ps1`: doctor de
  diagnóstico de saúde do cliente Dropbox (processo, instalação, espaço em disco,
  arquivos-problema, frescor de pastas críticas, conectividade, proxy, exclusão no
  Defender, hora do sistema) e auditoria de arquivos por atributos NTFS/Cloud Files
  (`SomenteNuvem`/`LocalENuvem`/`Indeterminado`), com reparo guiado em Modo Assistido
  (reiniciar processo, excluir do Defender). Cinco funções públicas novas em
  `WbaToolkit.Maintenance` (BCK-060)
- `Export-ToolkitDocumentation -Mode Help`: gera `manuais/portal.pt-BR.json` (catálogo de
  funções e scripts com ajuda curta/longa) e `manuais/categorias.pt-BR.json`; cria
  `manuais/glossario.pt-BR.md` se ainda não existir (ADR-0013)
- `tools/lint-check.sh`: roda PSScriptAnalyzer sobre `modules/` e `scripts/`, bloqueando
  em erros de severidade Error (ADR-0016)

### Corrigido
- Coluna de erro do relatório HTML de conectividade podia ficar em branco por colisão de
  `$error` (variável automática do PowerShell) em `ConvertTo-ConnectivityReportHtml.ps1`
- BOM UTF-8 ausente em `New-ToolkitElevationCommand.ps1` e em dois arquivos de teste com
  acentuação (ADR-0007)

### Alterado
- Mensagens de sucesso/falha de `remover-perfis-inativos.ps1`, `limpar-windows.ps1` e
  `atualizar-windows.ps1` padronizadas com `Write-Ok`/`Write-Fail` em vez de `Write-Host`
  colorido cru (ADR-0021)

## [v2.0.3] — 2026-07-05

> Versão PATCH. Implementa a ADR-0012 (`spec-win-toolkit`): migra os relatórios HTML e o
> portal de documentação de CSS artesanal para Tailwind CSS, compilado localmente via
> Tailwind CLI standalone (sem Node.js como dependência de distribuição — só de build,
> mesmo papel que pandoc/lualatex já ocupam para o manual PDF). Sem mudança de comportamento
> funcional; ajuste visual/de manutenibilidade do CSS.

### Adicionado
- `tools/tailwind/input.css`: fonte do CSS dos relatórios (config CSS-first do Tailwind
  v4 + `@layer base` para elementos sem classe explícita, ex. conteúdo Markdown convertido)
- `tools/build-report-css.sh`: compila o CSS via Tailwind CLI standalone e o embute em
  `ConvertTo-ConnectivityReportHtml.ps1`/`ConvertTo-StaticDocsHtml.ps1` entre marcadores
  `TAILWIND-CSS:BEGIN`/`END`, com guarda contra caracteres que quebrariam o here-string
- `tests/unit/WbaToolkit.Networking.Tests.ps1`: teste de sincronia entre as cores usadas
  nos cards de resumo do relatório de conectividade e o mapeamento de classes Tailwind

### Corrigido
- `modules/WbaToolkit.Core/Private/New-PortalIndexHtml.ps1`: classe `.card-grid` morta
  (nunca definida em nenhum `<style>`) fazia o grid de ferramentas do portal nunca aplicar
  layout; corrigida para uma utility Tailwind real durante a migração
- `modules/WbaToolkit.Networking/Private/ConvertTo-ConnectivityReportHtml.ps1`: `bg-white`
  e a cor de status (`bg-slate-200`/`bg-green-100`/etc.) no mesmo elemento são utilities do
  mesmo grupo com especificidade igual — o vencedor depende da ordem de declaração no CSS
  compilado, não da ordem no atributo `class`; `bg-white` removido dos cards de resumo
  (a cor de status sempre está presente, tornando-o redundante e conflitante)

### Alterado
- Todos os módulos alinhados para **ModuleVersion 2.0.3** (regra de alinhamento do
  processo de release)

## [v2.0.2] — 2026-07-03

> Versão PATCH. Revisão de código completa (análise estática com PSScriptAnalyzer + revisão
> manual dirigida por agentes) sobre todos os módulos e scripts operacionais. Corrige bugs de
> robustez, um gate de segurança fail-open e um bug sistêmico de quoting no relançamento elevado.
> Sem mudança de comportamento esperado para o operador em uso normal.

### Adicionado
- `modules/WbaToolkit.Core`: `New-ToolkitElevationCommand` — monta a linha de comando de
  relançamento elevado via `-Command` (em vez de `-File`), preservando parâmetros com espaços,
  aspas e arrays (`[string[]]`) intactos no processo elevado

### Corrigido
- **Bug sistêmico de quoting no relançamento elevado** (14 scripts: `analisar-espaco-disco`,
  `atualizar-windows`, `configurar-idioma-regional`, `diagnosticar-ad-cliente`,
  `diagnosticar-disco-100`, `diagnosticar-grafico`, `diagnosticar-memoria`,
  `gerenciar-inicializacao`, `gerenciar-login-automatico`, `inventario-hardware-software`,
  `limpar-windows`, `limpar-winsxs`, `remover-perfis-inativos`, `verificar-atualizacoes-hardware`):
  parâmetros array (ex.: `-Drive C,D`) e valores com espaço eram colapsados num único argumento
  ao relançar elevado via `-File`, silenciosamente quebrando a seleção de múltiplos discos e
  caminhos com espaço; todos migrados para `New-ToolkitElevationCommand`
- `modules/WbaToolkit.Identity/Private/Test-PrivilegedAccount.ps1`: falha na consulta CIM
  (WMI degradado) fazia o gate de segurança do autologon abrir sem confirmação (fail-open);
  agora falha fechado (trata como privilegiada) e avisa o operador
- `modules/WbaToolkit.Identity/Public/Enable-Autologon.ps1` e `Set-Autologon.ps1`: contas de
  **domínio** nunca exigiam confirmação de risco (a verificação local de privilégio não se
  aplica a elas); adicionado aviso e confirmação explícita também para contas de domínio
- `scripts/gerenciar-login-automatico.ps1` e `modules/WbaToolkit.Identity/Public/Invoke-AutologonManager.ps1`:
  senha lida via `Read-Host -AsSecureString` sobrescrevia a variável automática `$PWD`
  (diretório atual); renomeada para `$securePassword`
- `modules/WbaToolkit.Networking/Private/Get-ConnectivitySummary.ps1`: contadores de resumo
  (`Success`, `Failed`, `Warning`, etc.) retornavam `$null` em vez de `0` quando nenhum
  resultado tinha aquela classificação, em Windows PowerShell 5.1 — linhas em branco no
  relatório e lógica condicional afetada
- `modules/WbaToolkit.Core/Public/Invoke-ExternalCommand.ps1`: resolução do comando não
  restringia a `-CommandType Application`, podendo executar um alias/função com o mesmo nome
  em vez do executável nativo (ex.: `sc` como alias de `Set-Content` em PS 5.1 Desktop)
- `modules/WbaToolkit.Maintenance/Public/Invoke-EventLogMaintenance.ps1`: modo `ErrorOnly` não
  verificava o código de saída do `wevtutil epl` (backup) antes de limpar o log — falha
  silenciosa no backup não impedia a limpeza, perdendo os eventos de erro
- `modules/WbaToolkit.Maintenance/Public/Invoke-FilesystemCheck.ps1`: agendamento de `chkdsk`
  reportava sucesso ao operador mesmo quando o comando falhava (código de saída não verificado)
- `scripts/atualizar-windows.ps1`: linha órfã em `Invoke-WinGetUpgrade` fazia a função retornar
  um array de 2 objetos em vez de um `PSCustomObject`, reportando "Falha total" mesmo com
  upgrade WinGet 100% bem-sucedido
- `scripts/diagnosticar-ad-cliente.ps1`: reparo do canal seguro (secure channel) não atualizava
  o resultado do check original — `Get-AdHealthSummary` continuava calculando estado crítico
  após reparo bem-sucedido, e o modo assistido pedia a senha e repetia o reparo duas vezes
- `scripts/diagnosticar-grafico.ps1`: `Get-GfxProbableCategory` não reconhecia os rótulos de
  categoria `GPU`, `Assinatura` e `TDR`, retornando "Inconclusivo" nos achados mais críticos
- `scripts/diagnosticar-disco-100.ps1`: `Register-HD100ChkdskRepair` não respeitava `-DryRun`
  (sempre pedia confirmação real); `Get-HD100BankPlugins` comparava `'core.exe'` contra
  `Get-Process.Name` (que nunca inclui extensão), nunca detectando o plugin bancário
- `scripts/preparar-imagem-windows.ps1`: relatório final de sucesso usava o scan de ambiente
  anterior à remoção de bloqueadores Appx, listando bloqueadores já removidos como presentes
- `scripts/analisar-espaco-disco.ps1`: varredura de cache de navegador fixa em `C:\Users` em
  vez de `$env:SystemDrive\Users`
- `scripts/diagnosticar-memoria.ps1`: falha ao listar processos era mascarada como lista vazia
  (0 processos) em vez de propagar o erro
- `docs/adr/`: ADR local (`0021-ajuda-inline-parametros-portugues.md`) removida do repositório
  de código — especificações não devem existir dentro de `wba-windows-toolkit`; conteúdo
  preservado como ADR-0026 em `spec-win-toolkit`

### Alterado
- `manuais/manual-operador-wba-windows-toolkit.pdf`: corpo do texto passa a usar fonte sem
  serifa (Libertinus Sans, com fallback para Latin Modern Sans)

## [v2.0.1] — 2026-06-26

> Versão PATCH. Correções de bugs descobertos em uso pós-v2.0.0 e padronização da ajuda
> inline (`-Help`) em todos os scripts oficiais (ADR-0026 (spec-win-toolkit)), sem mudança de comportamento
> nas funções dos módulos.

### Adicionado
- Parâmetro `-Help` padronizado em **todos os 17 scripts** operacionais: ajuda inline em português, uma linha por parâmetro e exemplos de uso; encerra antes de qualquer verificação de elevação (ADR-0026 (spec-win-toolkit))

### Corrigido
- `scripts/gerenciar-drivers.ps1`: relatório HTML voltava com "Error formatting a string" — o operador `-f` era passado diretamente como argumento de método (`.AppendLine(...)`), fazendo as vírgulas separarem argumentos do método; agrupado entre parênteses
- `scripts/inventario-hardware-software.ps1`: mesmo problema na tabela Markdown (`-f` dentro de `.Add(...)`); agrupado entre parênteses
- `scripts/testar-conectividade-internet.ps1`: resolução da raiz do repositório subia dois níveis (resquício do layout antigo), apontando para fora do projeto e quebrando o `Import-Module` do WbaToolkit.Networking; ajustado para um nível (layout `scripts/`, ADR 0022)
- `scripts/inventario-hardware-software.ps1` e `scripts/diagnosticar-ad-cliente.ps1`: `#Requires -RunAsAdministrator` forçava elevação até para `-Help`; a exigência de administrador passou a ser verificada após o despacho do `-Help`, permitindo consultar a ajuda sem privilégios (ADR-0026 (spec-win-toolkit))
- `modules/WbaToolkit.Inventory/WbaToolkit.Inventory.psd1`: arquivo regravado com BOM UTF-8 (ADR 0007)

### Alterado
- Todos os módulos alinhados para **ModuleVersion 2.0.1** (regra de alinhamento do processo de release)

## [v2.0.0] — 2026-06-25

> Versão MAJOR. Unifica as duas linhas de desenvolvimento (GitHub e Codeberg, que haviam
> divergido em forks independentes) numa **linha canônica única** com a estrutura achatada
> `scripts/` em kebab-case (ADR 0022). Os caminhos e nomes de scripts antigos
> (`maintenance/`, `diagnostics/`, PascalCase) deixam de existir — daí o incremento de major.

### Adicionado
- `modules/WbaToolkit.Identity`: novo módulo de identidade/acesso local com **logon automático (autologon)** — senha protegida por segredo LSA (`Get-AutologonStatus`, `Enable-Autologon`, `Disable-Autologon`, `Set-Autologon`, `Invoke-AutologonManager`) (ADR 0023/0024)
- `scripts/gerenciar-login-automatico.ps1`: script operador para habilitar, desabilitar e editar o autologon, com salvaguardas
- `modules/WbaToolkit.Maintenance`: recuperado o **ciclo de remoção de bloqueadores Appx do Sysprep (BCK-022)** — `Get-SysprepAppxProvisioningIssue`, `Test-SysprepEnvironment -AppxPolicy`, reset de `secedit`, limpeza de GPO/AutoLogon e captura de SID; validado em Windows 10/PS 5.1 real
- `scripts/atualizar-windows.ps1`: spinner animado com cronômetro HH:MM:SS durante as atualizações winget/choco (`Invoke-ProcessWithSpinner`)
- `scripts/diagnosticar-ad-cliente.ps1`: reparo guiado de hora (time sync) e do canal seguro (secure channel) no diagnóstico de cliente de domínio
- `modules/WbaToolkit.Core`: `Write-Step` promovido a função pública do Core (marcador textual `[NN%]`, ADR-0021 do spec-win-toolkit — "padronizar feedback ao operador"), eliminando cópias locais nos scripts

### Alterado
- **Estrutura de scripts unificada**: todos os scripts operacionais migrados para `scripts/` em nomes verbo-objeto kebab-case (ADR 0022) — ex.: `maintenance/Preparar-Imagem-Windows.ps1` → `scripts/preparar-imagem-windows.ps1`, `diagnostics/Diagnostico-Memoria.ps1` → `scripts/diagnosticar-memoria.ps1`. **17 scripts** no total
- Inventário de hardware/software movido para `scripts/inventario-hardware-software.ps1` + módulo `WbaToolkit.Inventory`
- `regfiles/` movido para a raiz do projeto, corrigindo a referência da preparação de imagem
- `modules/WbaToolkit.Core`: escrita de arquivos padronizada via `Write-TextFileUtf8` (UTF-8 com BOM, ADR 0007)
- Todos os módulos alinhados para **ModuleVersion 2.0.0** (regra de alinhamento do processo de release)
- Manuais do operador alinhados ao estado atual (17 scripts, 6 módulos) e PDF regenerado

### Corrigido
- `modules/WbaToolkit.Maintenance`: `AppXSvc` é iniciado antes da pré-verificação de bloqueadores Appx do Sysprep (serviço sob demanda podia estar parado e bloquear o Sysprep sem bloqueador real)
- `xtudo.ps1`: normalização dos argumentos repassados aos scripts do launcher
- `scripts/atualizar-windows.ps1`: resumo final protegido contra objetos de resultado incompletos
- `modules/WbaToolkit.Core`: geradores de documentação apontados para os scripts atuais; inventário tornado portável nos geradores

### Removido
- Scaffolding experimental vazio e scripts não migrados; registro `não-validado` atualizado
- Caminhos/nomes de scripts no layout antigo (`maintenance/`, `diagnostics/`, `utilities/`, `configuration/`, `inventory/`, `updates/` e nomes PascalCase) — substituídos pelo layout `scripts/` (mudança incompatível)

## [v1.4.0] — 2026-06-23

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
- `scripts/Inventario-Hardware-Software.ps1`: desreferência de objetos CIM nulos (ex.: `Win32_BaseBoard` em VMs) lançava `PropertyNotFoundException` sob `Set-StrictMode 2.0` na geração do HTML; campos de placa-mãe, BIOS, computador e SO resolvidos com guarda (validação operacional)

### Alterado
- Aplicado UTF-8 com BOM a todos os `.ps1`/`.psm1`/`.psd1` que estavam sem BOM, em conformidade com o ADR 0007 (DEV-020)
- `tests/unit/WbaToolkit.Maintenance.Tests.ps1`: testes de `Remove-SafePath` atualizados para o novo contrato de whitelist e adicionado teste de recusa fora das raízes permitidas
- `utilities/Analise-Espaco-Disco.ps1` e `scripts/Inventario-Hardware-Software.ps1`: parâmetro padronizado para `-Path` com `[Alias('DiretorioSaida')]`, substituindo `-OutputDir` e alinhando aos demais scripts
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
