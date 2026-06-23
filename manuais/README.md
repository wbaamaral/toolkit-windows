# Catálogo de Documentação — WBA Windows Toolkit

Autor: **wbaamaral**

## Estrutura

```text
manuais/
├── README.md                  — este catálogo
├── operador/                  — guias para operadores de campo
├── referencia/                — referência técnica de módulos e funções
├── manual-operador-wba-windows-toolkit.md  — manual completo do operador
└── manual-operador-wba-windows-toolkit.pdf  — PDF do manual completo
```

## Portal do operador

Destinado a técnicos e suporte que executam scripts operacionais no campo.

Entrada recomendada do MVP: [`../xtudo.ps1`](../xtudo.ps1)
Entrada documental do operador: [`operador/README.md`](operador/README.md)

| Documento | Finalidade |
|---|---|
| [`operador/README.md`](operador/README.md) | Porta de entrada do operador no MVP |
| [`manual-operador-wba-windows-toolkit.md`](manual-operador-wba-windows-toolkit.md) | Manual completo do operador |
| [`operador/guia-rapido.md`](operador/guia-rapido.md) | Referência rápida por função operacional |

## Referência técnica

Destinada a desenvolvedores que estendem ou mantêm os módulos.

| Documento | Finalidade |
|---|---|
| [`referencia/modulos.md`](referencia/modulos.md) | Catálogo de módulos e funções públicas |
| Gerado por `Export-ToolkitDocumentation` | Portal HTML offline completo: portal operacional + referência técnica (executar no Windows) |
| Gerado por `Export-ToolkitFunctionDocs` | Apenas referência HTML das funções com CBH (usado internamente pelo comando acima) |

## Scripts do MVP

Os itens abaixo são os atalhos oficiais que o operador deve usar hoje.

| Script | Caminho | Descrição |
|---|---|---|
| Limpeza do Windows | `scripts/limpar-windows.ps1` | Limpeza conservadora e manutenção |
| Limpeza WinSxS | `scripts/limpar-winsxs.ps1` | Component Store: diagnóstico, limpeza assistida e relatório |
| Diagnóstico HD100 | `scripts/diagnosticar-disco-100.ps1` | Uso de disco 100%, SMART, startup |
| Diagnóstico de memória | `scripts/diagnosticar-memoria.ps1` | Top-N consumidores de RAM; métricas de memória paginada e física |
| Diagnóstico de driver gráfico | `scripts/diagnosticar-grafico.ps1` | GPU, DWM, TDR, WHEA, eventos gráficos, DXDiag |
| Diagnóstico de conectividade | `scripts/testar-conectividade-internet.ps1` | Testa gateway, DNS, ICMP, TCP; relatório HTML |
| Verificar atualizações de hardware | `scripts/verificar-atualizacoes-hardware.ps1` | BIOS, drivers e atualizações de hardware pendentes via Windows Update |
| Preparar imagem corporativa | `scripts/preparar-imagem-windows.ps1` | Tweaks de perfil Default + sysprep |
| Atualizar Windows | `scripts/atualizar-windows.ps1` | Windows Update e Chocolatey quando disponível |

## Fora do MVP

Ferramentas ainda não promovidas ficam fora deste catálogo operacional e seguem em
`experimental/` até passarem para a superfície oficial.

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
