# WBA Windows Toolkit — v1.1.4

> **v1.1.4** · PowerShell 5.1 · Windows 10 / Server 2016+

---

## 📦 O que está nesta versão

| Módulo | Versão | Funções | Descrição |
|---|---|---|---|
| `WbaToolkit.Core` | 1.1.3 | 24 | Funções base: saída padronizada, logging, sessão, relatórios, utilitários e documentação HTML |
| `WbaToolkit.Networking` | 1.1.3 | 16 | Diagnóstico de conectividade TCP/UDP/ICMP/DNS, wizard e exportação de relatórios |
| `WbaToolkit.Startup` | 1.1.3 | 7 | Gerenciamento de itens de inicialização do Windows |
| `WbaToolkit.Maintenance` | 1.1.3 | 5 | Preparação de imagem corporativa para sysprep |
| **Total** | | **52** | |

---

## 🛠️ Scripts operacionais (13 scripts)

### 🔍 Diagnóstico
| Script | Descrição |
|---|---|
| `diagnostics\Diagnostico-Driver-Grafico.ps1` | GPU, DWM, TDR, WHEA — tela preta e congelamento gráfico |
| `diagnostics\networking\Testar-Conectividade-Internet.ps1` | ICMP, DNS, TCP; relatório HTML de conectividade |
| `maintenance\Diagnostico-Reparo-HD100.ps1` | Disco 100%: saúde, processos, startup, ações assistidas |

### 🧹 Manutenção
| Script | Descrição |
|---|---|
| `maintenance\limpeza-windows.ps1` | Temporários, logs antigos, cache de miniaturas e do Windows Update |
| `maintenance\Gerenciar-Inicializacao-Windows.ps1` | Interface assistida para gerenciar startup do Windows |
| `maintenance\Preparar-Imagem-Windows.ps1` | Tweaks de perfil Default + sysprep para imagem corporativa |

### 📋 Inventário
| Script | Descrição |
|---|---|
| `inventory\Inventario-Hardware-Software.ps1` | Hardware, software e drivers — HTML, TXT, Markdown e JSON |

### 🏢 Active Directory
| Script | Descrição |
|---|---|
| `active-directory\Diagnostico-GPO-Client.ps1` | Verifica aplicação de GPO no cliente |
| `active-directory\Testa-Repara-ContaMaquinaAD.ps1` | Testa e repara conta de máquina no domínio |

### ⚙️ Configuração · 🔧 Utilitários · 🔄 Atualizações
| Script | Descrição |
|---|---|
| `configuration\Configurar-Idioma-Regional.ps1` | Idioma e configurações regionais do Windows |
| `utilities\Analise-Espaco-Disco.ps1` | Uso de espaço em disco por pasta |
| `utilities\Remover-Perfis-Inativos.ps1` | Remove perfis de usuário inativos |
| `updates\upgrade-windows.ps1` | Windows Update e Chocolatey (modo conservador) |

---

## 📋 O que mudou nesta versão

### v1.1.4 — Pipeline LaTeX e Manual do Operador revisado
- `tools/build-pdf.sh`: pipeline de geração de PDF em dois passos (Pandoc → .tex, latexmk → PDF) com validação de acentuação e documentação de dependências
- `docs/latex/preambulo.tex`: preâmbulo alinhado ao ADR 0019 — quebra automática em blocos de código, margens A4, cabeçalho/rodapé, tabelas com wrap
- `docs/manual-operador-wba-windows-toolkit.md`: revisão completa — 6 novas seções de scripts, parâmetros corrigidos, tabelas sem overflow
- `docs/manual-operador-wba-windows-toolkit.pdf`: regenerado com pipeline LaTeX; margens e blocos de código corrigidos

### v1.1.3 — RELEASE-NOTES.md atualizado para a versão corrente
- `RELEASE-NOTES.md` reflete a v1.1.3 e aplica a janela deslizante definida no processo de release

### v1.1.2 — Processo de release e artefatos formalizados
- `RELEASE-NOTES.md`: documento de apresentação da release publicado como corpo no Codeberg
- `tools/publish-codeberg-release.sh`: publica release via API do Codeberg (curl + Python)

---

## ⚡ Início rápido

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force

# Gerar portal de documentação HTML offline:
Export-ToolkitDocumentation -Mode All -Force
# Resultado em: .\docs\portal\index.html
```

---

## ✅ Requisitos

- Windows 10 / Windows Server 2016 ou superior
- Windows PowerShell 5.1 ou superior
- Permissões administrativas para a maioria das operações

---

## 📜 Autor

**Welyqrson Bastos Amaral** — Administrador de Sistemas · Infraestrutura · Automação · PowerShell
