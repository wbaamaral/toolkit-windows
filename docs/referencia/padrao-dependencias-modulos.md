# Padrão: Dependências de Módulos em Scripts

Autor: **wbaamaral**

## Problema

Scripts que dependem de módulos do toolkit (`WbaToolkit.Core`, `WbaToolkit.Networking`, etc.) falham silenciosamente quando o diretório `modules/` está ausente no clone do repositório. O `Import-Module` sem `-ErrorAction Stop` não interrompe a execução, e o script continua até encontrar uma função indefinida — gerando erros confusos como:

```
"Test-IsAdministrator" não é reconhecido como nome de cmdlet, função...
```

**Causa raiz:** Não existia um padrão documentado de validação de dependências. Cada script resolvia o import de forma diferente.

## Padrão obrigatório

Todo script que importa módulos do toolkit DEVE seguir este padrão:

```powershell
# === Dependencias: validar e carregar modulos do toolkit ===
$ToolkitRoot = Split-Path -Parent $PSScriptRoot

$CoreModulePath    = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
$SpecificModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.<Nome>/WbaToolkit.<Nome>.psd1'

# 1. Validar existência dos arquivos de módulo
foreach ($mod in @($CoreModulePath, $SpecificModulePath)) {
    if (-not (Test-Path -LiteralPath $mod)) {
        Write-Host "[FALHA] Modulo nao encontrado: $mod" -ForegroundColor Red
        Write-Host "        Solucao: verifique o clone do repositorio em $ToolkitRoot" -ForegroundColor Yellow
        exit 1
    }
}

# 2. Importar com tratamento de erro
try {
    Import-Module $CoreModulePath    -Force -ErrorAction Stop
    Import-Module $SpecificModulePath -Force -ErrorAction Stop
}
catch {
    Write-Host "[FALHA] Nao foi possivel carregar os modulos do toolkit." -ForegroundColor Red
    Write-Host "        Erro: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "        Solucao: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force" -ForegroundColor Yellow
    exit 1
}
```

## Regras

1. **`-ErrorAction Stop` é obrigatório** em todo `Import-Module` de módulo do toolkit. Sem ele, falhas de importação são silenciadas por `$ErrorActionPreference = 'Continue'`.

2. **`Test-Path` antes de importar**. Validar que o arquivo `.psd1` existe antes de tentar carregar. Mensagem de erro clara com caminho completo e solução.

3. **`try/catch` envolve o bloco de import**. Captura erros de PowerShell (ExecutionPolicy, módulo corrompido, versão incompatível) e exibe mensagem acionável.

4. **`exit 1` em falha**. Nunca continuar execução sem módulos carregados. Script sem dependências = script quebrado.

5. **`Split-Path -Parent $PSScriptRoot`** é o método correto para resolver `$ToolkitRoot`. Nunca usar caminhos absolutos hardcoded.

6. **Trailing backslash inconsistente**. Usar `/` (funciona em PS 5.1+ em qualquer OS) ou `Join-Path` sempre. Misturar `\` e `/` funciona mas é fonte de bugs em edge cases.

## Scripts corrigidos (2026-07-30)

| Script | Antes | Depois |
|--------|-------|--------|
| `inventario-hardware-software.ps1` | `-ErrorAction Stop` sem `Test-Path` | Padrão completo |
| `configurar-acesso-remoto.ps1` | Sem `-ErrorAction Stop` | Padrão completo |
| `gerenciar-copias.ps1` | Sem `-ErrorAction Stop` | Padrão completo |
| `gerenciar-agendamentos.ps1` | Sem `-ErrorAction Stop` | Padrão completo |
| `gerenciar-copia-sombra.ps1` | Sem `-ErrorAction Stop` | Padrão completo |

## Referência

- `detectar-ip-duplicado.ps1` — primeiro script a implementar o padrão (linha 137-164)
- Issue original: `inventario-hardware-software.ps1` falhava em clones onde `modules/` estava ausente

---

# Padrão: Estrutura de .psm1 para PS 5.1

## Problema

Módulos `.psm1` que usam `[CmdletBinding()] param()` no início falham **silenciosamente** no PowerShell 5.1. O `Import-Module` retorna sucesso (sem exceção), mas **nenhuma função é exportada**. O script que chama as funções recebe erro `CommandNotFoundException`.

**Causa raiz:** No PS 5.1, `[CmdletBinding()] param()` em `.psm1` pode interferir com `$PSScriptRoot` e com o dot-sourcing de arquivos `.ps1`. Combinado com `-ErrorAction SilentlyContinue` no `Get-ChildItem`, a falha é completamente mascarada.

## Padrão obrigatório para .psm1

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path -LiteralPath $privatePath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path -LiteralPath $publicPath) {
    foreach ($file in @(Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File)) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Funcao1',
    'Funcao2'
)
```

## Regras

1. **NUNCA usar `[CmdletBinding()] param()` em .psm1** — causa comportamento anômalo no PS 5.1.
2. **NUNCA usar `-ErrorAction SilentlyContinue` no `Get-ChildItem`** — mascara falha de leitura de arquivos.
3. **SEMPRE usar `Test-Path` antes de `Get-ChildItem`** — tolera pastas `Private/` ou `Public/` ausentes.
4. **SEMPRE usar `-LiteralPath`** — evita problemas com caracteres especiais no caminho.
5. **SEMPRE usar `-File`** — evita pegar diretórios por engano.
6. **BOM UTF-8 obrigatório** — todo `.psm1` DEVE ter BOM UTF-8 para PS 5.1 parsear corretamente.

## Módulos corrigidos (2026-07-30)

| Módulo | Problema | Correção |
|--------|----------|----------|
| `WbaToolkit.Core` | `param()` + `SilentlyContinue` | Padrão completo |
| `WbaToolkit.Inventory` | `param()` + `SilentlyContinue` | Padrão completo + Test-Path |
| `WbaToolkit.Networking` | `param()` + `SilentlyContinue` | Padrão completo + Test-Path |
| `WbaToolkit.Identity` | `SilentlyContinue` | Test-Path + `-LiteralPath` |
| `WbaToolkit.Licensing` | Sem Test-Path | Test-Path + `-LiteralPath` |
| `WbaToolkit.Maintenance` | `SilentlyContinue` | Test-Path + `-LiteralPath` |
| `WbaToolkit.Services` | `SilentlyContinue` no Private | Test-Path + `-LiteralPath` |
| `WbaToolkit.SSH` | Sem Test-Path | Test-Path + `-LiteralPath` |
| `WbaToolkit.Startup` | `SilentlyContinue` | Test-Path + `-LiteralPath` |
| `WbaToolkit.Backup` | Sem BOM | BOM adicionado |
| `WbaToolkit.ScheduledTask` | Sem BOM | BOM adicionado |
| `WbaToolkit.ShadowCopy` | Sem BOM | BOM adicionado |
