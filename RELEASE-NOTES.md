# WBA Windows Toolkit — v2.0.3

> **v2.0.3** · PowerShell 5.1 · Windows 10 / Server 2016+

---

## O que está nesta versão

| Módulo | Versão | Funções | Descrição |
|---|---|---|---|
| `WbaToolkit.Core` | 2.0.3 | 26 | Funções base: saída padronizada, logging, sessão, relatórios, utilitários e documentação HTML |
| `WbaToolkit.Networking` | 2.0.3 | 16 | Diagnóstico de conectividade TCP/UDP/ICMP/DNS, wizard e exportação de relatórios |
| `WbaToolkit.Startup` | 2.0.3 | 7 | Gerenciamento de itens de inicialização do Windows |
| `WbaToolkit.Maintenance` | 2.0.3 | 13 | Manutenção avançada: limpeza, WinSxS, sistema de arquivos e preparação de imagem (sysprep) |
| `WbaToolkit.Identity` | 2.0.3 | 5 | Identidade e acesso local: logon automático (autologon) com senha protegida por segredo LSA |
| `WbaToolkit.Inventory` | 2.0.3 | 1 | Mapa de cobertura para o inventário de hardware/software |
| **Total** | | **68** | |

---

## Scripts operacionais (17 scripts)

> A partir desta versão todos os scripts vivem em `scripts/` com nomes verbo-objeto
> kebab-case (ADR 0022) e podem ser abertos pelo launcher `xtudo.ps1`.

### Diagnóstico

| Script | Descrição |
|---|---|
| `scripts\diagnosticar-grafico.ps1` | GPU, DWM, TDR, WHEA — tela preta e congelamento gráfico |
| `scripts\diagnosticar-memoria.ps1` | Top-N consumidores de RAM; métricas de memória paginada e física |
| `scripts\diagnosticar-disco-100.ps1` | Disco 100%: saúde, processos, startup e ações assistidas |
| `scripts\diagnosticar-ad-cliente.ps1` | Cliente de domínio: GPO, canal seguro, sincronização de hora e reparo guiado |
| `scripts\testar-conectividade-internet.ps1` | ICMP, DNS, TCP; relatório HTML de conectividade |
| `scripts\verificar-atualizacoes-hardware.ps1` | BIOS, drivers e atualizações de hardware pendentes via Windows Update |

### Manutenção

| Script | Descrição |
|---|---|
| `scripts\limpar-windows.ps1` | Temporários, logs e cache — funções reutilizáveis no WbaToolkit.Maintenance |
| `scripts\limpar-winsxs.ps1` | Component Store: diagnóstico, limpeza assistida e relatório |
| `scripts\gerenciar-drivers.ps1` | Backup e restauração de drivers OEM via DISM/pnputil |
| `scripts\preparar-imagem-windows.ps1` | Tweaks de perfil Default + sysprep para imagem corporativa, com remoção de bloqueadores Appx |

### Inicialização e Identidade

| Script | Descrição |
|---|---|
| `scripts\gerenciar-inicializacao.ps1` | Interface assistida para gerenciar startup e serviços do Windows |
| `scripts\gerenciar-login-automatico.ps1` | Habilita, desabilita e edita o logon automático (autologon) com salvaguardas |

### Inventário

| Script | Descrição |
|---|---|
| `scripts\inventario-hardware-software.ps1` | Hardware, software e drivers — HTML, TXT, Markdown e JSON |

### Configuração · Utilitários · Atualizações

| Script | Descrição |
|---|---|
| `scripts\configurar-idioma-regional.ps1` | Idioma e configurações regionais do Windows |
| `scripts\analisar-espaco-disco.ps1` | Uso de espaço em disco por pasta/arquivo (somente leitura) |
| `scripts\remover-perfis-inativos.ps1` | Remove perfis de usuário inativos |
| `scripts\atualizar-windows.ps1` | Atualização geral via winget/Chocolatey/Windows Update, com spinner e cronômetro |

---

## O que mudou nesta versão

### v2.0.3 — Relatórios HTML migrados para Tailwind CSS local

> Versão PATCH. Implementa a ADR-0012 (`spec-win-toolkit`): CSS artesanal dos relatórios e
> do portal de documentação substituído por Tailwind CSS, compilado localmente via CLI
> standalone (sem Node.js na distribuição — só de build, mesmo papel do pandoc/lualatex
> para o manual PDF). Sem mudança de comportamento funcional.

**Adicionado:**

| Artefato | Descrição |
|---|---|
| `tools/tailwind/input.css` | Fonte do CSS dos relatórios (Tailwind v4 CSS-first + `@layer base`) |
| `tools/build-report-css.sh` | Compila e embute o CSS nos geradores de HTML |

**Corrigido:**

| Componente | Correção |
|---|---|
| `New-PortalIndexHtml.ps1` | Classe `.card-grid` morta (nunca definida) — grid do portal nunca aplicava layout |
| `ConvertTo-ConnectivityReportHtml.ps1` | `bg-white` conflitava com a cor de status nos cards de resumo (utilities de mesmo grupo, especificidade igual) |

**Alterado:**

| Componente | Alteração |
|---|---|
| Todos os módulos | Alinhados para `ModuleVersion 2.0.3` |

### v2.0.2 — Revisão de código completa: relançamento elevado, segurança do autologon e robustez

> Versão PATCH. Revisão de código dos 6 módulos e 17 scripts (análise estática + revisão
> manual). Corrige um bug sistêmico de quoting no relançamento elevado, um gate de segurança
> fail-open no autologon e bugs de robustez pontuais. Sem mudança de comportamento esperado
> para o operador em uso normal.

**Adicionado:**

| Artefato | Descrição |
|---|---|
| `New-ToolkitElevationCommand` (Core) | Monta a linha de comando de relançamento elevado via `-Command`, preservando arrays e valores com espaço |

**Corrigido:**

| Componente | Correção |
|---|---|
| 14 scripts operacionais | Relançamento elevado via `-File` colapsava parâmetros array (`-Drive C,D`) e valores com espaço num único argumento; migrados para `New-ToolkitElevationCommand` |
| `Test-PrivilegedAccount` (Identity) | Falha na consulta CIM abria o gate de segurança do autologon sem confirmação (fail-open); agora falha fechado |
| `Enable-Autologon` / `Set-Autologon` (Identity) | Contas de domínio nunca exigiam confirmação de risco; adicionado aviso explícito |
| `gerenciar-login-automatico.ps1` / `Invoke-AutologonManager` | Senha sobrescrevia a variável automática `$PWD`; renomeada para `$securePassword` |
| `Get-ConnectivitySummary` (Networking) | Contadores retornavam `$null` em vez de `0` em PS 5.1 quando nenhum resultado tinha a classificação |
| `Invoke-ExternalCommand` (Core) | Resolução de comando não restringia a `-CommandType Application` |
| `Invoke-EventLogMaintenance` / `Invoke-FilesystemCheck` (Maintenance) | Códigos de saída de `wevtutil`/`chkdsk` não verificados antes de reportar sucesso |
| `atualizar-windows.ps1` | `Invoke-WinGetUpgrade` retornava array de 2 objetos por linha órfã, reportando falha total mesmo com sucesso |
| `diagnosticar-ad-cliente.ps1` | Reparo do canal seguro não atualizava o check original (estado crítico persistia após reparo) |
| `diagnosticar-grafico.ps1` | Categorias `GPU`, `Assinatura` e `TDR` não reconhecidas em `Get-GfxProbableCategory` |
| `diagnosticar-disco-100.ps1` | `Register-HD100ChkdskRepair` ignorava `-DryRun`; `Get-HD100BankPlugins` nunca detectava o plugin bancário |
| `preparar-imagem-windows.ps1` | Relatório final usava scan anterior à remoção de bloqueadores Appx |
| `analisar-espaco-disco.ps1` | Cache de navegador varria `C:\Users` fixo em vez de `$env:SystemDrive\Users` |
| `diagnosticar-memoria.ps1` | Falha ao listar processos mascarada como lista vazia |

### v2.0.1 — Ajuda inline padronizada e correções de relatórios

> Versão PATCH. Padroniza a ajuda inline (`-Help`) em todos os scripts e corrige bugs
> descobertos em uso pós-v2.0.0, sem alterar o comportamento das funções dos módulos.

**Adicionado:**

| Artefato | Descrição |
|---|---|
| `-Help` em todos os scripts | Ajuda inline em português nos 17 scripts: uso, uma linha por parâmetro e exemplos; encerra antes de qualquer verificação de elevação (ADR-0026 (spec-win-toolkit)) |

**Corrigido:**

| Componente | Correção |
|---|---|
| `gerenciar-drivers.ps1` | Relatório HTML voltava com "Error formatting a string": o `-f` era passado direto como argumento de `.AppendLine(...)` (vírgulas viravam separadores de argumento); agrupado entre parênteses |
| `inventario-hardware-software.ps1` | Mesmo problema na tabela Markdown (`-f` dentro de `.Add(...)`); agrupado entre parênteses |
| `testar-conectividade-internet.ps1` | Raiz do repositório era resolvida dois níveis acima (resquício do layout antigo), quebrando o `Import-Module` do Networking; ajustado para um nível (ADR 0022) |
| `inventario` e `diagnosticar-ad-cliente` | `#Requires -RunAsAdministrator` exigia elevação até para `-Help`; verificação de admin movida para após o despacho do `-Help` |
| `WbaToolkit.Inventory.psd1` | Regravado com BOM UTF-8 (ADR 0007) |

**Alterado:**

| Componente | Alteração |
|---|---|
| Todos os módulos | Alinhados para `ModuleVersion 2.0.1` |

---

### v2.0.0 — Linha canônica única, autologon e Sysprep BCK-022

> Versão MAJOR. As duas linhas de desenvolvimento (GitHub e Codeberg, que haviam divergido
> em forks independentes) foram unificadas numa **linha canônica única**, com a estrutura
> achatada `scripts/` em kebab-case (ADR 0022). Os caminhos e nomes antigos
> (`maintenance/`, `diagnostics/`, PascalCase) deixam de existir.

**Adicionado:**

| Artefato | Descrição |
|---|---|
| `WbaToolkit.Identity` | Novo módulo com logon automático (autologon): `Get-AutologonStatus`, `Enable-Autologon`, `Disable-Autologon`, `Set-Autologon`, `Invoke-AutologonManager` — senha protegida por segredo LSA (ADR 0023/0024) |
| `scripts\gerenciar-login-automatico.ps1` | Script operador para habilitar/desabilitar/editar o autologon com salvaguardas |
| Sysprep BCK-022 | Ciclo de remoção de bloqueadores Appx recuperado: `Get-SysprepAppxProvisioningIssue`, `Test-SysprepEnvironment -AppxPolicy`, reset de `secedit`, limpeza de GPO/AutoLogon e captura de SID |
| `scripts\atualizar-windows.ps1` | Spinner animado com cronômetro HH:MM:SS nas atualizações winget/choco |
| `scripts\diagnosticar-ad-cliente.ps1` | Reparo guiado de hora e do canal seguro no diagnóstico de cliente de domínio |
| `WbaToolkit.Core` | `Write-Step` promovido a função pública (marcador `[NN%]`, ADR-0021 do spec-win-toolkit — "padronizar feedback ao operador") |

**Alterado:**

| Componente | Alteração |
|---|---|
| Estrutura de scripts | Todos os 17 scripts migrados para `scripts/` em kebab-case (ex.: `maintenance\Preparar-Imagem-Windows.ps1` → `scripts\preparar-imagem-windows.ps1`) |
| `WbaToolkit.Inventory` | Inventário movido para `scripts\inventario-hardware-software.ps1` + módulo dedicado |
| `regfiles/` | Movido para a raiz do projeto, corrigindo a preparação de imagem |
| `WbaToolkit.Core` | Escrita de arquivos padronizada via `Write-TextFileUtf8` (UTF-8 com BOM) |
| Todos os módulos | Alinhados para `ModuleVersion 2.0.0` |
| Manuais | Alinhados ao estado atual (17 scripts, 6 módulos) e PDF regenerado |

**Corrigido:**

| Componente | Correção |
|---|---|
| Sysprep | `AppXSvc` é iniciado antes da pré-verificação de bloqueadores Appx (serviço sob demanda podia bloquear o Sysprep sem bloqueador real) |
| `xtudo.ps1` | Normalização dos argumentos repassados aos scripts |
| `atualizar-windows.ps1` | Resumo final protegido contra objetos de resultado incompletos |
| `WbaToolkit.Core` | Geradores de documentação apontados para os scripts atuais; inventário portável |

**Removido:**

| Item | Detalhe |
|---|---|
| Layout antigo | `maintenance/`, `diagnostics/`, `utilities/`, `configuration/`, `inventory/`, `updates/` e nomes PascalCase — substituídos por `scripts/` (mudança incompatível) |
| Scaffolding experimental | Pastas vazias e scripts não migrados removidos |

---

### v1.4.0 — Xtudo como linha principal, diagnóstico AD e manuais alinhados

| Artefato | Descrição |
|---|---|
| `xtudo.ps1` | Launcher único do toolkit com atalhos rápidos e busca por palavra-chave |
| `scripts/` | Promoção do MVP para camada oficial do operador (limpar, diagnosticar, preparar imagem, atualizar etc.) |
| `updates/upgrade-windows.ps1` | Reescrito com backend resolvido (Auto/WinGet/Chocolatey/All), detecção de reboot e códigos de saída padronizados (BCK-018) |
| `tools/release-check.sh` | Pré-voo anti-LFS que bloqueia ponteiros de texto antes de tag/publicação |

---

## Início rápido

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

# Launcher único (lista e abre os scripts por categoria ou busca):
.\xtudo.ps1

# Ou direto, por exemplo:
.\scripts\diagnosticar-memoria.ps1 -Top 10          # top 10 consumidores de RAM
.\scripts\limpar-winsxs.ps1 -Modo Diagnostico       # WinSxS (somente leitura)
.\scripts\gerenciar-login-automatico.ps1            # autologon (habilitar/editar)
.\scripts\gerenciar-drivers.ps1 -Modo Backup        # backup de drivers OEM

# Gerar portal de documentação HTML offline:
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
Export-ToolkitDocumentation -Mode All -Force
```

---

## Requisitos

- Windows 10 / Windows Server 2016 ou superior
- Windows PowerShell 5.1 ou superior
- Permissões administrativas para a maioria das operações

---

## Autor

**Welyqrson Bastos Amaral** — Administrador de Sistemas · Infraestrutura · Automação · PowerShell
