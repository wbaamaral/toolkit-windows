# Catálogo de Documentação — WBA Windows Toolkit

Autor: **wbaamaral**

## Estrutura

```text
docs/
├── manual/
│   ├── README.md              — este catálogo
│   ├── operador/              — guias para operadores de campo
│   └── referencia/            — referência técnica de módulos e funções
├── manual-operador-wba-windows-toolkit.md  — manual completo do operador (PDF incluído)
└── legenda-padronizacao-git.txt            — convenções de commits
```

## Portal do operador

Destinado a técnicos e suporte que executam scripts operacionais no campo.

| Documento | Finalidade |
|---|---|
| [`../manual-operador-wba-windows-toolkit.md`](../manual-operador-wba-windows-toolkit.md) | Manual completo do operador |
| [`operador/guia-rapido.md`](operador/guia-rapido.md) | Referência rápida por função operacional |

## Referência técnica

Destinada a desenvolvedores que estendem ou mantêm os módulos.

| Documento | Finalidade |
|---|---|
| [`referencia/modulos.md`](referencia/modulos.md) | Catálogo de módulos e funções públicas |
| Gerado por `Export-ToolkitDocumentation` | Portal HTML offline completo: portal operacional + referência técnica (executar no Windows) |
| Gerado por `Export-ToolkitFunctionDocs` | Apenas referência HTML das funções com CBH (usado internamente pelo comando acima) |

## Scripts por função operacional

### Diagnóstico

| Script | Caminho | Descrição |
|---|---|---|
| Diagnóstico de conectividade | `diagnostics/networking/Testar-Conectividade-Internet.ps1` | Testa gateway, DNS, ICMP, TCP; relatório HTML |
| Diagnóstico de driver gráfico | `diagnostics/Diagnostico-Driver-Grafico.ps1` | GPU, DWM, TDR, WHEA, eventos gráficos, DXDiag |
| Diagnóstico de memória | `diagnostics/Diagnostico-Memoria.ps1` | Top-N consumidores de RAM; métricas de memória paginada e física |
| Verificar atualizações de hardware | `diagnostics/Verificar-Atualizacoes-Hardware.ps1` | BIOS, drivers e atualizações de hardware pendentes via Windows Update |

### Manutenção

| Script | Caminho | Descrição |
|---|---|---|
| Limpeza do Windows | `maintenance/limpeza-windows.ps1` | Limpeza conservadora e manutenção |
| Limpeza WinSxS | `maintenance/Limpeza-WinSxS.ps1` | Component Store: diagnóstico, limpeza assistida e relatório |
| Backup e restauração de drivers | `maintenance/Backup-Restaurar-Drivers.ps1` | Backup e restauração de drivers não-Windows via DISM/pnputil |
| Diagnóstico HD100 | `maintenance/Diagnostico-Reparo-HD100.ps1` | Uso de disco 100%, SMART, startup |
| Gerenciar inicialização | `maintenance/Gerenciar-Inicializacao-Windows.ps1` | Habilitar/desabilitar itens de startup |
| Preparar imagem corporativa | `maintenance/Preparar-Imagem-Windows.ps1` | Tweaks de perfil Default + sysprep |

### Inventário

| Script | Caminho | Descrição |
|---|---|---|
| Inventário hardware/software | `inventory/Inventario-Hardware-Software.ps1` | Coleta completa; HTML/PDF opcional |

### Active Directory

| Script | Caminho | Descrição |
|---|---|---|
| Diagnóstico de GPO | `active-directory/Diagnostico-GPO-Client.ps1` | Diagnóstico de aplicação de políticas |
| Reparo de conta de máquina | `active-directory/Testa-Repara-ContaMaquinaAD.ps1` | Teste e reparo de conta no domínio |

### Configuração

| Script | Caminho | Descrição |
|---|---|---|
| Idioma e região | `configuration/Configurar-Idioma-Regional.ps1` | Padronização de idioma e fuso |

### Utilitários

| Script | Caminho | Descrição |
|---|---|---|
| Análise de espaço em disco | `utilities/Analise-Espaco-Disco.ps1` | Análise por pasta e disco |
| Remover perfis inativos | `utilities/Remover-Perfis-Inativos.ps1` | Remove perfis de usuários inativos |

### Atualizações

| Script | Caminho | Descrição |
|---|---|---|
| Atualizar Windows | `updates/upgrade-windows.ps1` | Windows Update e Chocolatey quando disponível |

## Módulos PowerShell

| Módulo | Funções públicas | Uso |
|---|---|---|
| `WbaToolkit.Core` | 24 | Funções base compartilhadas por todos os scripts |
| `WbaToolkit.Networking` | 16 | Diagnóstico de conectividade e relatórios de rede |
| `WbaToolkit.Startup` | 7 | Gerenciamento de itens de inicialização do Windows |
| `WbaToolkit.Maintenance` | 13 | Manutenção avançada: limpeza, WinSxS, sistema de arquivos e preparação de imagem |

## Geração de documentação HTML local

No Windows (PowerShell 5.1):

```powershell
# Portal completo (portal operacional + referência técnica):
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1
Export-ToolkitDocumentation -Mode All -Force
# Resultado em: .\docs\portal\index.html

# Apenas referência técnica CBH:
Export-ToolkitDocumentation -Mode TechnicalReference -Force
# Resultado em: .\docs\portal\referencia\index.html
```
