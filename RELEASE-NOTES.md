# WBA Windows Toolkit — v1.2.0

> **v1.2.0** · PowerShell 5.1 · Windows 10 / Server 2016+

---

## O que está nesta versão

| Módulo | Versão | Funções | Descrição |
|---|---|---|---|
| `WbaToolkit.Core` | 1.2.0 | 24 | Funções base: saída padronizada, logging, sessão, relatórios, utilitários e documentação HTML |
| `WbaToolkit.Networking` | 1.2.0 | 16 | Diagnóstico de conectividade TCP/UDP/ICMP/DNS, wizard e exportação de relatórios |
| `WbaToolkit.Startup` | 1.2.0 | 7 | Gerenciamento de itens de inicialização do Windows |
| `WbaToolkit.Maintenance` | 1.2.0 | 13 | Manutenção avançada: limpeza, WinSxS, sistema de arquivos e preparação de imagem |
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

### v1.2.0 — Novos scripts, WinSxS, correções PS 5.1 e conformidade

**Adicionado:**
- `Diagnostico-Memoria.ps1`: top-N consumidores de RAM com métricas de memória paginada
- `Verificar-Atualizacoes-Hardware.ps1`: diagnóstico somente leitura de BIOS e drivers pendentes
- `Backup-Restaurar-Drivers.ps1`: backup e restauração de drivers OEM via DISM/pnputil
- `Limpeza-WinSxS.ps1`: gestão assistida do Component Store (modos Diagnostico/Limpeza/Relatorio)
- `WbaToolkit.Maintenance`: 8 novas funções públicas — `Remove-SafePath`, `Get-DiskInfo`, `Get-FilesystemErrorEvent`, `Write-MaintenanceEvent`, `Invoke-FilesystemCheck`, `Invoke-EventLogMaintenance`, `Get-ComponentStoreInfo`, `Invoke-ComponentStoreCleanup`

**Corrigido:**
- Compatibilidade PS 5.1: 25 ocorrências de `[Generic.List/Stack[T]]::new()` substituídas por `New-Object` em 11 arquivos
- `Invoke-EventLogMaintenance`: hashtable inline com backtick causava ParserError no PS 5.1
- 6 scripts sem bloco de identificação ADR 0006 (`$ScriptName`/`$ScriptPath`/`$ScriptDir`)
- 45 arquivos `.ps1` com UTF-8 BOM restaurado (ADR 0007)

### v1.1.4 — Pipeline LaTeX e Manual do Operador revisado
- `tools/build-pdf.sh`: pipeline de geração de PDF (Pandoc + LuaLaTeX)
- `docs/manual-operador-wba-windows-toolkit.md`: revisão completa com 6 novas seções

### v1.1.3 — RELEASE-NOTES.md atualizado para versão corrente
- `RELEASE-NOTES.md` reflete v1.1.3 com janela deslizante

---

## Início rápido

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force

# Limpeza do WinSxS (diagnóstico somente leitura):
.\maintenance\Limpeza-WinSxS.ps1 -Modo Diagnostico

# Diagnóstico de memória:
.\diagnostics\Diagnostico-Memoria.ps1 -Top 10

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
