# WBA Windows Toolkit — v1.3.0

> **v1.3.0** · PowerShell 5.1 · Windows 10 / Server 2016+

---

## O que está nesta versão

| Módulo | Versão | Funções | Descrição |
|---|---|---|---|
| `WbaToolkit.Core` | 1.3.0 | 24 | Funções base: saída padronizada, logging, sessão, relatórios, utilitários e documentação HTML |
| `WbaToolkit.Networking` | 1.3.0 | 16 | Diagnóstico de conectividade TCP/UDP/ICMP/DNS, wizard e exportação de relatórios |
| `WbaToolkit.Startup` | 1.3.0 | 7 | Gerenciamento de itens de inicialização do Windows |
| `WbaToolkit.Maintenance` | 1.3.0 | 13 | Manutenção avançada: limpeza, WinSxS, sistema de arquivos e preparação de imagem |
| **Total** | | **60** | |

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
| `updates\upgrade-windows.ps1` | Windows Update e Chocolatey (modo conservador) |

---

## O que mudou nesta versão

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
| `WbaToolkit.Startup` | Preservação de tipo nativo do registro (`REG_EXPAND_SZ`/`REG_BINARY`/`REG_DWORD`); `-WhatIf` real em Disable/Enable/Remove; `Enable-StartupItem` não recria chave Run existente |
| `Diagnostico-GPO-Client.ps1` | Regex de canal seguro super-escapada tornava detecção código morto; corrigido para `NERR_Success\|0x0` |
| `Diagnostico-Reparo-HD100.ps1` | `-Modo Rollback` chamava função inexistente; relatório HTML referenciava propriedades de sessão ausentes |
| `Testa-Repara-ContaMaquinaAD.ps1` | Erro de parse `[CmdletBinding()]` sem `param()` impedia carregamento do script |
| `Analise-Espaco-Disco.ps1` | Erro de parse `[CmdletBinding()]` sem `param()` impedia carregamento do script |

**Corrigido — compatibilidade PS 5.1 / validação operacional (DEV-020):**

| Componente | Correção |
|---|---|
| `limpeza-windows.ps1` | `Start-Transcript` sem `-Encoding` (parâmetro inexistente no PS 5.1) |
| `Invoke-ComponentStoreCleanup` | DISM em nível Standard sem prompt oculto; saída em tempo real; `Write-Progress` removido |
| `Test-IcmpConnectivity` | Latência de ping zerava no PS 7: seleciona `Latency` (PS 7+) ou `ResponseTime` (PS 5.1) em runtime |
| `Diagnostico-GPO-Client.ps1` | Mesma correção de latência ICMP |
| `Diagnostico-Reparo-HD100.ps1` | `-BasePath` tornado opcional; alinha ao contrato de `Initialize-ScriptSession` |
| `Analise-Espaco-Disco.ps1` | Totalizadores de volume zerados: `System.IO.DriveInfo` não possui `.Size`; corrigido para `TotalSize`/`TotalFreeSpace` |
| `Inventario-Hardware-Software.ps1` | Objetos CIM nulos (VMs sem `Win32_BaseBoard`) lançavam `PropertyNotFoundException`; campos protegidos com guarda |
| 45 arquivos `.ps1` | UTF-8 com BOM restaurado em conformidade com ADR 0007 |

**Alterado:**

| Componente | Alteração |
|---|---|
| `tests/unit/WbaToolkit.Maintenance.Tests.ps1` | Testes de `Remove-SafePath` atualizados para novo contrato de whitelist; teste de recusa fora das raízes adicionado |
| `tests/unit/WbaToolkit.Core.Tests.ps1` | Assertivas de `Format-FileSize` independentes de cultura (separador decimal é comportamento esperado) |
| `Analise-Espaco-Disco.ps1`, `Inventario-Hardware-Software.ps1` | Parâmetro padronizado para `-Path` com `[Alias('DiretorioSaida')]` |

---

### v1.2.0 — Novos scripts, WinSxS e conformidade PS 5.1

**Adicionado:**

| Artefato | Descrição |
|---|---|
| `diagnostics\Diagnostico-Memoria.ps1` | Top-N consumidores de RAM; métricas de memória paginada e física |
| `diagnostics\Verificar-Atualizacoes-Hardware.ps1` | BIOS, drivers e Windows Update — somente leitura |
| `maintenance\Backup-Restaurar-Drivers.ps1` | Backup e restauração de drivers OEM via DISM/pnputil; `-DryRun` e `-GerarHtml` |
| `maintenance\Limpeza-WinSxS.ps1` | Gestão assistida do Component Store: modos Diagnostico, Limpeza, Relatorio |
| `WbaToolkit.Maintenance` | 8 novas funções: `Remove-SafePath`, `Get-DiskInfo`, `Get-FilesystemErrorEvent`, `Write-MaintenanceEvent`, `Invoke-FilesystemCheck`, `Invoke-EventLogMaintenance`, `Get-ComponentStoreInfo`, `Invoke-ComponentStoreCleanup` |

**Corrigido:**

| Componente | Correção |
|---|---|
| 11 arquivos | 25 ocorrências de `[Generic.List/Stack[T]]::new()` substituídas por `New-Object` (ParserError no PS 5.1) |
| `Invoke-EventLogMaintenance` | Hashtable inline com backtick causava `Token '}' inesperado` no PS 5.1 |
| 6 scripts | Bloco de identificação `$ScriptName`/`$ScriptPath`/`$ScriptDir` ausente (ADR 0006) |
| 45 arquivos `.ps1` | UTF-8 BOM restaurado (ADR 0007) |

---

## Início rápido

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force

# Diagnóstico de memória (top 10 processos):
.\diagnostics\Diagnostico-Memoria.ps1 -Top 10

# Limpeza do WinSxS (somente leitura):
.\maintenance\Limpeza-WinSxS.ps1 -Modo Diagnostico

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
