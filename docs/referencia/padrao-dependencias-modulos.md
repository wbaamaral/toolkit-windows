# Padrão: Dependências de Módulos em Scripts

Autor: **wbaamaral**

> **ATENÇÃO:** Este documento é um resumo. A especificação completa e atualizada está em
> [`spec/qualidade/padrao-dependencias-modulos.md`](../../../spec/qualidade/padrao-dependencias-modulos.md).

## Regra central

**Scripts operacionais NÃO usam `Import-Module` para carregar módulos do toolkit.**
Usar **dot-source direto** dos arquivos `.ps1`.

```powershell
# === Dependencias: dot-source direto ===
$ToolkitRoot = Split-Path -Parent $PSScriptRoot

$coreModuleRoot = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core'

foreach ($dir in @($coreModuleRoot)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Host "[FALHA] Modulo nao encontrado: $dir" -ForegroundColor Red
        exit 1
    }
}

try {
    foreach ($moduleRoot in @($coreModuleRoot)) {
        foreach ($sub in @('Private', 'Public')) {
            $dir = Join-Path $moduleRoot $sub
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File |
                    ForEach-Object { . $_.FullName }
            }
        }
    }
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}
```

## Regras obrigatórias (resumo)

| # | Regra | Motivo |
|---|-------|--------|
| R1 | NUNCA `[CmdletBinding()] param()` em `.psm1` | Falha silenciosa no PS 5.1 |
| R2 | NUNCA `-ErrorAction SilentlyContinue` em `Get-ChildItem` de carregamento | Mascara falha, exporta 0 funções |
| R3 | SEMPRE `Test-Path` antes de `Get-ChildItem` | Tolera pastas ausentes |
| R4 | NUNCA `PSObject.Properties.Name -contains 'X'` com StrictMode | `PropertyNotFoundStrict` em objeto vazio |
| R5 | Scripts usam dot-source, não `Import-Module` | Elimina 5 pontos de falha silenciosa |
| R6 | BOM UTF-8 obrigatório em `.ps1`/`.psm1` | PS 5.1 não parseia sem BOM |

## Referência completa

- [ADR 0032 — Substituir Import-Module por dot-source](../../../spec/adr/0032-substituir-import-module-por-dot-source.md)
- [`spec/qualidade/padrao-dependencias-modulos.md`](../../../spec/qualidade/padrao-dependencias-modulos.md) — Especificação completa
- [`spec/qualidade/processo-modificacao-codigo.md`](../../../spec/qualidade/processo-modificacao-codigo.md) — Processo de modificação
