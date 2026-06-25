# WBA Windows Toolkit — v2.0.0

> **v2.0.0** · PowerShell 5.1 · Windows 10 / Server 2016+

---

## O que está nesta versão

| Módulo | Versão | Funções | Descrição |
|---|---|---|---|
| `WbaToolkit.Core` | 2.0.0 | 25 | Funções base: saída padronizada, logging, sessão, relatórios, utilitários e documentação HTML |
| `WbaToolkit.Networking` | 2.0.0 | 16 | Diagnóstico de conectividade TCP/UDP/ICMP/DNS, wizard e exportação de relatórios |
| `WbaToolkit.Startup` | 2.0.0 | 7 | Gerenciamento de itens de inicialização do Windows |
| `WbaToolkit.Maintenance` | 2.0.0 | 13 | Manutenção avançada: limpeza, WinSxS, sistema de arquivos e preparação de imagem (sysprep) |
| `WbaToolkit.Identity` | 2.0.0 | 5 | Identidade e acesso local: logon automático (autologon) com senha protegida por segredo LSA |
| `WbaToolkit.Inventory` | 2.0.0 | 1 | Mapa de cobertura para o inventário de hardware/software |
| **Total** | | **67** | |

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
| `WbaToolkit.Core` | `Write-Step` promovido a função pública (marcador `[NN%]`, ADR 0021) |

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

### v1.3.0 — Validação operacional, hardening de segurança e laboratório AD

| Componente | Mudança |
|---|---|
| `Invoke-Safe` | Detecção de falha de comando nativo (código morto eliminado) |
| `Remove-SafePath` | Whitelist de raízes, anti path-traversal, `-WhatIf` real |
| `WbaToolkit.Startup` | Preservação de tipo nativo do registro; `-WhatIf` real |
| `tests/lab-ad/` | Provisionamento de laboratório AD (DC + cliente) para validação em domínio real |
| 45 arquivos `.ps1` | UTF-8 com BOM restaurado (ADR 0007) |

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
