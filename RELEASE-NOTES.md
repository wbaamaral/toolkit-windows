# WBA Windows Toolkit — v1.4.0

> **v1.4.0** · PowerShell 5.1 · Windows 10 / Server 2016+

---

## O que está nesta versão

| Módulo | Versão | Funções | Descrição |
|---|---|---|---|
| `WbaToolkit.Core` | 1.4.0 | 25 | Funções base: saída padronizada, logging, sessão, relatórios, utilitários e documentação HTML |
| `WbaToolkit.Networking` | 1.4.0 | 16 | Diagnóstico de conectividade TCP/UDP/ICMP/DNS, wizard e exportação de relatórios |
| `WbaToolkit.Startup` | 1.4.0 | 7 | Gerenciamento de itens de inicialização do Windows |
| `WbaToolkit.Maintenance` | 1.4.0 | 13 | Manutenção avançada: limpeza, WinSxS, sistema de arquivos e preparação de imagem |
| **Total** | | **61** | |

---

## Scripts operacionais (17 scripts)

### Diagnóstico

| Script | Descrição |
|---|---|
| `diagnostics\Diagnostico-Driver-Grafico.ps1` | GPU, DWM, TDR, WHEA — tela preta e congelamento gráfico |
| `diagnostics\Diagnostico-Memoria.ps1` | Top-N consumidores de RAM; métricas de memória paginada e física |
| `diagnostics\Verificar-Atualizacoes-Hardware.ps1` | BIOS, drivers e atualizações de hardware pendentes via Windows Update |
| `diagnostics\networking\Testar-Conectividade-Internet.ps1` | ICMP, DNS, TCP; relatório HTML de conectividade |
| `maintenance\Diagnostico-Reparo-HD100.ps1` | Disco 100%: saúde, processos, startup, ações assistidas |

### Manutenção

| Script | Descrição |
|---|---|
| `maintenance\limpeza-windows.ps1` | Temporários, logs, cache — funções reutilizáveis no WbaToolkit.Maintenance |
| `maintenance\Limpeza-WinSxS.ps1` | Component Store: diagnóstico, limpeza assistida e relatório |
| `maintenance\Backup-Restaurar-Drivers.ps1` | Backup e restauração de drivers não-Windows via DISM/pnputil |
| `maintenance\Gerenciar-Inicializacao-Windows.ps1` | Interface assistida para gerenciar startup do Windows |
| `maintenance\Preparar-Imagem-Windows.ps1` | Tweaks de perfil Default + sysprep para imagem corporativa |

### Inventário

| Script | Descrição |
|---|---|
| `inventory\Inventario-Hardware-Software.ps1` | Hardware, software e drivers — HTML, TXT, Markdown e JSON |

### Active Directory

| Script | Descrição |
|---|---|
| `active-directory\Diagnostico-GPO-Client.ps1` | Verifica aplicação de GPO no cliente |
| `active-directory\Testa-Repara-ContaMaquinaAD.ps1` | Testa e repara conta de máquina no domínio |

### Configuração · Utilitários · Atualizações

| Script | Descrição |
|---|---|
| `configuration\Configurar-Idioma-Regional.ps1` | Idioma e configurações regionais do Windows |
| `utilities\Analise-Espaco-Disco.ps1` | Uso de espaço em disco por pasta |
| `utilities\Remover-Perfis-Inativos.ps1` | Remove perfis de usuário inativos |
| `updates\upgrade-windows.ps1` | Upgrade via WinGet, Chocolatey ou ambos — com detecção de reboot pendente |

---

## O que mudou nesta versão

### v1.4.0 — Validação PS 5.1, upgrade completo, Write-Step e correções de robustez

**Adicionado:**

| Artefato | Descrição |
|---|---|
| `WbaToolkit.Core\Public\Write-Step.ps1` | Nova função `Write-Step -Message -Percent`: marcador `[NN%]` em Cyan, sem `Write-Progress` (ADR 0021) |
| `spec/qualidade/padrao-feedback-operador.md` | Especificação de UX ao operador: limiar 15 s, cores padronizadas, uso de `Write-Step` vs `Write-Progress` |
| `tests/unit/WbaToolkit.Core.Tests.ps1` | 4 novos testes para `Write-Step` (export + 3 comportamentos) |
| `tests/unit/WbaToolkit.Maintenance.Tests.ps1` | 2 novos testes `Invoke-EventLogMaintenance -Action Ask` em contexto não-interativo (BCK-021) |
| `Invoke-ProcessWithSpinner` | Spinner animado (`\|/-`) com contador `[HH:MM:SS]` durante execução de WinGet e Chocolatey; output exibido após conclusão |

**Reescrito:**

| Componente | Descrição |
|---|---|
| `updates\upgrade-windows.ps1` | Reescrito com TDD/DDD: backends WinGet, Chocolatey, All; ações UpgradeAll/ListOnly/Select; detecção de reboot pendente; 62/62 testes Pester PS 5.1 e PS 7.6.2; spinner com timer validado em produção real (PS 7.6.3, TI02) |

**Corrigido:**

| Componente | Correção |
|---|---|
| `Invoke-EventLogMaintenance` | NullArrayIndex em `-Action Ask` via SSH: `do-while` guarded com `IsNullOrEmpty`; `ContainsKey` antes do lookup (BCK-021) |
| `Invoke-ChocolateyUpgrade` / `Invoke-WinGetUpgrade` | Output stream contaminava retorno da função → `PropertyNotFoundException` no resumo com StrictMode 2.0; corrigido com `Invoke-ProcessWithSpinner` |
| `Invoke-WinGetUpgrade` | PSCustomObject orphan emitido como segundo retorno da função — removido |
| `Get-ServiceStartupState` | Injeção WQL via nomes de serviço com aspas simples: `$safeName = $name -replace "'","''"` (BCK-014) |
| `Write-ScriptLog` | Encoding explícito (`-Encoding UTF8`) no `Add-Content` (BCK-014) |
| `Export-ToolkitDocumentation` | UTF-8 com BOM via `[UTF8Encoding]::new($true)` (BCK-014) |
| `WbaToolkit.Networking` | 3 correções de robustez: IP parsing, DNS timeout, ICMP multi-target (BCK-010) |
| `WbaToolkit.Startup` | Preservação de tipo de registro e compatibilidade PS 5.1 (BCK-011) |
| `Invoke-DefaultUserHiveOp` | Robustez do hive do perfil Default: guarda contra caminho nulo e arquivo ausente (BCK-009) |
| `Invoke-ComponentStoreCleanup` | Parsing de saída DISM independente de idioma — regex substituída por presença de exit code 0 (BCK-008) |
| `limpeza-windows.ps1` | Remoção de cópia local de `Write-Step`; uso da função canônica do Core (BCK-020) |
| `Configurar-Idioma-Regional.ps1` | Remoção de cópia local de `Write-Step` com `Write-Progress` interno (não-conforme ADR 0021) (BCK-020) |
| `tests/unit/WbaToolkit.Maintenance.Tests.ps1` | Mock de `Read-Host` com `-ModuleName 'WbaToolkit.Maintenance'` para interceptar dentro do módulo |

**Validado em PS 5.1 real (Windows 10 pt-BR, DESKTOP-9QHD8H2):**

| Artefato | Resultado |
|---|---|
| Pester Core + Maintenance | 122/125 (2 `Read-UserInput` SSH — artefato de ambiente; 1 skip) |
| Pester upgrade-windows.ps1 | 62/62 |
| Pester limpeza-windows.ps1 | 61/62 (1 skip) |
| 9 scripts diagnóstico/manutenção | Execução real OK |

---

### v1.3.0 — Validação operacional, hardening de segurança e laboratório AD

**Adicionado:**

| Artefato | Descrição |
|---|---|
| `tests/lab-ad/` | Scripts de provisionamento de laboratório AD (DC + cliente membro) e runbook para validar `Diagnostico-GPO-Client.ps1` e `Testa-Repara-ContaMaquinaAD.ps1` em domínio real |

**Corrigido — revisão de código (DEV-019):**

| Componente | Correção |
|---|---|
| `Invoke-Safe` | Detecção de falha de comando nativo: `$LASTEXITCODE` local mascarava o global — código morto eliminado |
| `Remove-SafePath` | Whitelist de raízes permitidas, canonicalização anti path-traversal, recusa de raízes críticas, `-WhatIf` real |
| `WbaToolkit.Startup` | Preservação de tipo nativo do registro; `-WhatIf` real em Disable/Enable/Remove |
| `Diagnostico-GPO-Client.ps1` | Regex de canal seguro super-escapada tornava detecção código morto |
| `Diagnostico-Reparo-HD100.ps1` | `-Modo Rollback` chamava função inexistente; relatório HTML com propriedades ausentes |
| `Testa-Repara-ContaMaquinaAD.ps1` | Erro de parse `[CmdletBinding()]` sem `param()` impedia carregamento |
| `Analise-Espaco-Disco.ps1` | Erro de parse `[CmdletBinding()]` sem `param()` impedia carregamento |

**Corrigido — compatibilidade PS 5.1 / validação operacional (DEV-020):**

| Componente | Correção |
|---|---|
| `limpeza-windows.ps1` | `Start-Transcript` sem `-Encoding` (parâmetro inexistente no PS 5.1) |
| `Invoke-ComponentStoreCleanup` | DISM em nível Standard sem prompt oculto; saída em tempo real; `Write-Progress` removido |
| `Test-IcmpConnectivity` | Latência de ping zerava no PS 7: seleciona `Latency` (PS 7+) ou `ResponseTime` (PS 5.1) em runtime |
| `Analise-Espaco-Disco.ps1` | Totalizadores de volume zerados: corrigido para `TotalSize`/`TotalFreeSpace` |
| `Inventario-Hardware-Software.ps1` | Objetos CIM nulos (VMs sem `Win32_BaseBoard`) lançavam `PropertyNotFoundException` |
| 45 arquivos `.ps1` | UTF-8 com BOM restaurado em conformidade com ADR 0007 |

---

## Início rápido

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force

# Diagnóstico de memória (top 10 processos):
.\diagnostics\Diagnostico-Memoria.ps1 -Top 10

# Limpeza assistida:
.\maintenance\limpeza-windows.ps1

# Upgrade do sistema (WinGet + Chocolatey):
.\updates\upgrade-windows.ps1 -Backend All -Action UpgradeAll

# Backup de drivers OEM:
.\maintenance\Backup-Restaurar-Drivers.ps1 -Modo Backup

# Gerar portal de documentação HTML offline:
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
