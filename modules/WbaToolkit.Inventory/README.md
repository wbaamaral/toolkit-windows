# WbaToolkit.Inventory

Módulo de inventário técnico do Xtudo.

Esse módulo concentra funções ligadas à cobertura do inventário e à evolução
do escopo, sem misturar o entrypoint operacional do operador.

## Funções públicas

| Função | Uso |
|---|---|
| `Get-InventoryCoverageMap` | Retorna os blocos cobertos e, opcionalmente, as lacunas conhecidas |

## Uso

```powershell
Import-Module .\modules\WbaToolkit.Inventory\WbaToolkit.Inventory.psd1 -Force
Get-InventoryCoverageMap
Get-InventoryCoverageMap -IncludeGaps
```
