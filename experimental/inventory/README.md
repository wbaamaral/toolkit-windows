# inventory

Scripts de inventário de hardware e software. Coletam informações detalhadas do equipamento e do ambiente Windows, gerando relatórios estruturados para documentação de ativos, auditorias e suporte técnico.

---

## Scripts

### `Inventario-Hardware-Software.ps1`

**Função:** Gera inventário completo de hardware e software em relatório HTML com conversão opcional para PDF.

**Principais ações:**

| Seção coletada | Dados incluídos |
|---|---|
| Sistema Operacional | Nome, versão, build, arquitetura, data de instalação, uptime |
| Processador | Fabricante, modelo, núcleos físicos/lógicos, frequência, cache |
| Memória RAM | Total, módulos instalados, capacidade por slot, frequência |
| Placa-mãe | Fabricante, modelo, número de série |
| BIOS | Fabricante, versão, data de lançamento |
| Armazenamento | Discos físicos (modelo, tamanho, tipo), volumes lógicos com uso e barras de capacidade |
| GPU | Fabricante, modelo, memória dedicada, resolução atual |
| Rede | Adaptadores, IP, MAC, gateway, DNS, status |
| Monitores | Fabricante, modelo, resolução nativa |
| Software instalado | Nome, versão, fabricante, data de instalação (com filtro em tempo real) |
| Atualizações | Histórico recente de Windows Update instaladas |
| Serviços | Serviços com início automático e status atual |

**Saída gerada:**
- **HTML** — relatório com design responsivo, índice de navegação e barras de uso de disco coloridas
- **PDF** — conversão automática via Chrome ou Microsoft Edge em modo headless (quando disponível)
- **Resumo de hardware e drivers** — saída enxuta opcional em TXT, Markdown e JSON

**Parâmetros:**

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `-OutputDir` | `ReportsRoot` ou `C:\WBA\Relatorios` | Raiz de relatórios; o script cria `Inventory\<timestamp>` |
| `-NaoPDF` | — | Gera apenas HTML, sem tentar converter para PDF |
| `-GerarResumoHardwareDrivers` | — | Gera o inventário completo e também o resumo enxuto de hardware e drivers |
| `-SomenteHardwareDrivers` | — | Gera apenas o resumo enxuto, sem HTML/PDF do inventário completo |
| `-FormatoResumoHardwareDrivers` | `Todos` | `Txt`, `Markdown`, `Json` ou `Todos` |

**Uso básico:**

```powershell
# Relatório na pasta padronizada (HTML + PDF se Chrome/Edge disponível)
.\Inventario-Hardware-Software.ps1

# Somente HTML, sem PDF
.\Inventario-Hardware-Software.ps1 -NaoPDF

# Relatório em diretório personalizado (inclusive compartilhamento de rede)
.\Inventario-Hardware-Software.ps1 -OutputDir "\\servidor\inventario$"

# Inventário completo e resumo enxuto de hardware/drivers
.\Inventario-Hardware-Software.ps1 -GerarResumoHardwareDrivers

# Apenas resumo rápido para campo
.\Inventario-Hardware-Software.ps1 -SomenteHardwareDrivers

# Apenas Markdown para colar em chamado, issue ou relatório técnico
.\Inventario-Hardware-Software.ps1 -SomenteHardwareDrivers -FormatoResumoHardwareDrivers Markdown

# HTML completo sem PDF e resumo enxuto
.\Inventario-Hardware-Software.ps1 -NaoPDF -GerarResumoHardwareDrivers
```

**Resumo de hardware e drivers:** indicado para comparação antes/depois de atualização de driver, diagnóstico de tela preta, congelamento gráfico, falhas do DWM, falhas de vídeo e inventário rápido em campo.

**Arquivos do resumo:** `resumo-hardware-drivers.txt`, `resumo-hardware-drivers.md` e/ou `resumo-hardware-drivers.json`.

**Requisitos:** Administrador local recomendado (dados de hardware exigem privilégios elevados). Windows 10+. PowerShell 5.1+.

**Log:** `C:\WBA\Relatorios\Inventory\<timestamp>\logs\inventario-<timestamp>.log` ou `<OutputDir>\Inventory\<timestamp>\logs\...`
