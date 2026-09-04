# Carta de Especificação e Correção de Bugs — WBA Windows Toolkit

**Data:** 2026-09-03  
**Ambiente reportado:** `FINANCEIRO04` | `GRUPOFORMATE\welyqrson.amaral` | Wi-Fi `192.168.1.101/24` | Windows PowerShell 5.1  
**Toolkit:** `wba-windows-toolkit` @ `main` (commit `ad878d9`)  
**Operador:** `xtudo.ps1` (launcher) + scripts `scripts/*` + módulos `modules/WbaToolkit.*`  
**Solicitante:** sessão `xtudo.ps1` opções **7**, **10**, **4** em `C:\ti\toolkit-windows`  
**Autor da análise:** Muse Spark (model `muse-spark-1.2`) — verificação executada localmente

---

## 1. Resumo executivo

Foram reportados **3 falhas** em única sessão do `xtudo.ps1`:

| # | Atalho | Script | Erro | Severidade |
|---|--------|--------|------|------------|
| BUG-001 | 7 — Testar conectividade internet | `scripts/testar-conectividade-internet.ps1:170` via `xtudo.ps1:406` | `Não é possível chamar um método em uma expressão de valor nulo.` + resumo `Total:15 Sucesso:1` divergente dos 15 `[Success]` listados | Alta — quebra geração de `conectividade-internet.txt`, relatório inconsistente |
| BUG-002 | 10 — Gerenciar cópia de sombra (VSS) | `scripts/gerenciar-copia-sombra.ps1` via `xtudo.ps1:486` | `Invoke-XtudoScript : Não é possível validar o argumento no parâmetro 'Acao'. O argumento "-Acao" não pertence ao conjunto "Diagnostico;Criar;...".` | Alta — launcher não consegue despachar nenhum script com `-Acao` |
| BUG-003 | 4 — Diagnosticar gráfico | `scripts/diagnosticar-grafico.ps1` via `xtudo.ps1:486` | `... parâmetro 'Modo'. O argumento "-Modo" não pertence ao conjunto "Diagnostico;Assistido".` | Alta — mesmo root de BUG-002 para `-Modo` |

**Root causes distintos:** 2 raízes.

- **R1 — Contrato quebrado entre `Invoke-ConnectivityTest` e `testar-conectividade-internet.ps1` + bug de contagem em `Get-ConnectivitySummary`** (BUG-001).
- **R2 — `xtudo.ps1:Invoke-XtudoScript` usa *array splatting* para parâmetros nomeados, que o PowerShell trata como posicionais, falhando em `ValidateSet`** (BUG-002 e BUG-003).

Todas as correções foram aplicadas no branch de trabalho e validadas por reprodução isolada + testes unitários existentes.

---

## 2. Evidências (transcrição)

### 2.1 BUG-001 — Conectividade

```
Opcao ... : 7
Executando: Testar conectividade internet
...
RESUMO
Total        : 15
Sucesso      : 1
Falhas       : 0
...
RESULTADOS
[Success] Contexto de rede ...
[Success] Teste ICMP 8.8.8.8 ...
[Success] Teste ICMP 8.8.4.4 ...
[Success] Teste TCP nic.br:443 ...
... (15 linhas Success)
...
C:\ti\toolkit-windows\scripts\testar-conectividade-internet.ps1 : Não é possível chamar um método em uma expressão de valor nulo.
No C:\ti\toolkit-windows\xtudo.ps1:406 caractere:5
+     & $target @invokeArgs
```

### 2.2 BUG-002 — VSS

```
Opcao: 10
Executando: Gerenciar copia de sombra (VSS)
Invoke-XtudoScript : Não é possível validar o argumento no parâmetro 'Acao'.
O argumento "-Acao" não pertence ao conjunto "Diagnostico;Criar;Remover;..."
No C:\ti\toolkit-windows\xtudo.ps1:486 caractere:17
+                 Invoke-XtudoScript -Entry $quick[$idx]
```

### 2.3 BUG-003 — Gráfico

```
Opcao: 4
Executando: Diagnosticar gráfico
Invoke-XtudoScript : Não é possível validar o argumento no parâmetro 'Modo'.
O argumento "-Modo" não pertence ao conjunto "Diagnostico;Assistido"
No C:\ti\toolkit-windows\xtudo.ps1:486 ...
```

---

## 3. Análise técnica detalhada

### 3.1 R1a — `Get-ConnectivitySummary` conta incorretamente (`wba-windows-toolkit/modules/WbaToolkit.Networking/Private/Get-ConnectivitySummary.ps1:12-17`)

**Código vigente:**

```powershell
$grouped = $Results | Group-Object Classification
[pscustomobject]@{
    Total        = @($Results).Count
    Success      = @($grouped | Where-Object Name -eq 'Success').Count
    Failed       = @($grouped | Where-Object Name -eq 'Failed').Count
    # ... Warning, Inconclusive, Skipped, Error idem
}
```

**Diagnóstico:**

`Group-Object Classification` retorna `GroupInfo[]` com propriedades `Name`, `Count` (nº de itens no grupo) e `Group`.  
`Where-Object Name -eq 'Success'` retorna **um** `GroupInfo` (Count=15 quando todos Success).  
`@(...).Count` envolve o resultado em array e lê `Array.Count` (=1), não `GroupInfo.Count` (=15). Por isso `Success:1` quando deveria ser `15`.

Reproduzido em Linux `pwsh` com 15 `Success` mockados — retornou `Success=1`. A culpa não é de `Show-ConnectivityReport` (`Show-ConnectivityReport.ps1:40-44`) que apenas exibe `$Report.Summary.Success`, mas do produtor do resumo.

**Impacto:** relatório contraditório, operador desconfia da ferramenta; automações que consomem JSON tomam decisão errada.

### 3.2 R1b — `testar-conectividade-internet.ps1:170-178` quebra contrato (`wba-windows-toolkit/scripts/testar-conectividade-internet.ps1:168-180`)

**Código vigente:**

```powershell
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$lines.Add(('Gerado em       : {0}' -f $report.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')))
$lines.Add(('Computador      : {0}' -f $report.ComputerName))
$lines.Add(('Resultado geral : {0}' -f $report.OverallStatus))
...
foreach ($test in $report.Tests) {
    $status = if ($test.Success) { 'OK' } else { 'FALHA' }
    $lines.Add(('  [{0}] {1}' -f $status, $test.Name))
    if ($test.Detail) { $lines.Add(('        {0}' -f $test.Detail)) }
}
```

**Contrato real de `Invoke-ConnectivityTest` (`modules/WbaToolkit.Networking/Public/Invoke-ConnectivityTest.ps1:99-109`):**

```powershell
[pscustomobject]@{
    ReportId   = [guid]...
    StartedAt  = $startedAt        # [datetime]
    FinishedAt = $finishedAt       # [datetime]
    Detailed   = [bool]$Detailed
    Context    = $context          # Get-NetworkContext { Hostname, Username, InterfaceAlias, IPv4Address, ... }
    Results    = $resultItems      # New-ConnectivityResult[] { TestName, Classification, Target, Status, ... }
    Summary    = $summary          # Get-ConnectivitySummary
    Blocked    = $blocked
    BlockReason= $reason
}
```

Não existem `GeneratedAt`, `ComputerName`, `OverallStatus`, `Tests`, `Name`, `Detail`. Todos `$null`, logo `$report.GeneratedAt.ToString(...)` dispara `InvokeMethodOnNull` — exatamente o erro da linha `xtudo.ps1:406` (`& $target @invokeArgs` propaga exceção do script filho).

Histórico: a divergência existe desde o commit `8bb2f8b` (toolkit completo) e nunca foi sincronizada. O `Show-ConnectivityReport.ps1:30-36` usa corretamente `FinishedAt`, `Context.Hostname` etc., mas o bloco TXT foi escrito contra um contrato imaginário.

### 3.3 R2 — `xtudo.ps1:Invoke-XtudoScript` splatting incorreto (`wba-windows-toolkit/xtudo.ps1:360-391`)

**Código vigente:**

```powershell
$invokeArgs = @()
if ($null -ne $Entry.PSObject.Properties['Args']) {
    foreach ($arg in @($Entry.Args)) {
        $text = [string]$arg
        if ($text -match '^\-\S+\s+\S+$' -and $text -notmatch '["'']') {
            $invokeArgs += @($text -split '\s+', 2)
            continue
        }
        $invokeArgs += $text
    }
}
& $target @invokeArgs
```

Catálogo define `Args = @('-Acao','Diagnostico')` ou `@('-Modo','Diagnostico')` (`xtudo.ps1:66,83,148,173,214,223,232,241,250,267`).  
Após normalização, `$invokeArgs = @('-Acao','Diagnostico')`.  
`& $target @invokeArgs` faz *array splatting*: o PowerShell trata cada elemento como **posicional**, não como nomeado. Prova isolada no ambiente Linux `pwsh 7.6.5`:

```powershell
function Test-Func { param([ValidateSet('Diagnostico','Criar')][string]$Acao) ... }
$a=@('-Acao','Diagnostico'); Test-Func @a
# -> Cannot validate argument on parameter 'Acao'. The argument "-Acao" does not belong...
```

O mesmo falha para `& script.ps1 @array` e para `Get-ChildItem @array`. Apenas *hashtable splatting* (`@{Acao='Diagnostico'}` → `& $target @ht`) funciona para parâmetros nomeados.

Por isso `gerenciar-copia-sombra.ps1:70` (`[ValidateSet('Diagnostico','Criar',...)]`) e `diagnosticar-grafico.ps1:88` (`[ValidateSet('Diagnostico','Assistido')]`) recebem literal `"-Acao"`/`"-Modo"` como **valor** do parâmetro, violando o `ValidateSet`.

A linha citada nos logs (`xtudo.ps1:486`) é o chamador `Invoke-XtudoScript -Entry $quick[$idx]`; a exceção é atribuída ao chamador mas origina-se no `& $target @invokeArgs` dentro da função.

---

## 4. Correções aplicadas

### 4.1 `Get-ConnectivitySummary` — contagem correta

**Arquivo:** `wba-windows-toolkit/modules/WbaToolkit.Networking/Private/Get-ConnectivitySummary.ps1:1-27`

**Diff:**

```diff
-    $grouped = $Results | Group-Object Classification
-    [pscustomobject]@{
-        Total         = @($Results).Count
-        Success       = @($grouped | Where-Object Name -eq 'Success').Count
-        Failed        = @($grouped | Where-Object Name -eq 'Failed').Count
-        Warning       = @($grouped | Where-Object Name -eq 'Warning').Count
-        Inconclusive  = @($grouped | Where-Object Name -eq 'Inconclusive').Count
-        Skipped       = @($grouped | Where-Object Name -eq 'Skipped').Count
-        Error         = @($grouped | Where-Object Name -eq 'Error').Count
-    }
+    $grouped = $Results | Group-Object Classification
+    $map = @{}
+    foreach ($g in @($grouped)) {
+        if ($null -ne $g -and $null -ne $g.Name) {
+            $map[[string]$g.Name] = [int]$g.Count
+        }
+    }
+    [pscustomobject]@{
+        Total         = @($Results).Count
+        Success       = if ($map.ContainsKey('Success')) { $map['Success'] } else { 0 }
+        Failed        = if ($map.ContainsKey('Failed')) { $map['Failed'] } else { 0 }
+        Warning       = if ($map.ContainsKey('Warning')) { $map['Warning'] } else { 0 }
+        Inconclusive  = if ($map.ContainsKey('Inconclusive')) { $map['Inconclusive'] } else { 0 }
+        Skipped       = if ($map.ContainsKey('Skipped')) { $map['Skipped'] } else { 0 }
+        Error         = if ($map.ContainsKey('Error')) { $map['Error'] } else { 0 }
+    }
```

**Justificativa:** lê `GroupInfo.Count` diretamente, sem `@().Count`. Hashtab `map` evita repetição de `Where-Object` e lida com ausência de chave (0).

### 4.2 `testar-conectividade-internet.ps1` — alinhar ao contrato real

**Arquivo:** `wba-windows-toolkit/scripts/testar-conectividade-internet.ps1:166-200`

**Diff (trecho TXT):**

```diff
-$lines.Add(('Gerado em       : {0}' -f $report.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')))
-$lines.Add(('Computador      : {0}' -f $report.ComputerName))
-$lines.Add(('Resultado geral : {0}' -f $report.OverallStatus))
-$lines.Add('')
-$lines.Add('Testes:')
-foreach ($test in $report.Tests) {
-    $status = if ($test.Success) { 'OK' } else { 'FALHA' }
-    $lines.Add(('  [{0}] {1}' -f $status, $test.Name))
-    if ($test.Detail) { $lines.Add(('        {0}' -f $test.Detail)) }
-}
+$generatedAt = if ($null -ne $report.FinishedAt) { $report.FinishedAt } elseif ($null -ne $report.StartedAt) { $report.StartedAt } else { Get-Date }
+$computerName = if ($report.Context -and $report.Context.Hostname) { $report.Context.Hostname } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'N/I' }
+$overall = if ($report.Blocked) { 'BLOQUEADO: ' + $report.BlockReason }
+           elseif ($report.Summary) {
+               if ($report.Summary.Failed -gt 0 -or $report.Summary.Error -gt 0) { 'FALHA' }
+               elseif ($report.Summary.Warning -gt 0) { 'AVISO' }
+               else { 'OK' }
+           } else { 'N/I' }
+
+ $lines.Add(('Gerado em       : {0}' -f $generatedAt.ToString('yyyy-MM-dd HH:mm:ss')))
+ $lines.Add(('Computador      : {0}' -f $computerName))
+ $lines.Add(('Resultado geral : {0}' -f $overall))
+ if ($report.Summary) {
+     $lines.Add(('Resumo          : Total={0} Sucesso={1} Falhas={2} Avisos={3} Inconclusivo={4}' -f $report.Summary.Total, $report.Summary.Success, $report.Summary.Failed, $report.Summary.Warning, $report.Summary.Inconclusive))
+ }
+ $lines.Add('Testes:')
+ foreach ($test in @($report.Results)) {
+     $testName = if ($test.TestName) { $test.TestName } elseif ($test.Name) { $test.Name } else { 'Teste' }
+     $status = if ($test.Success) { 'OK' } else { 'FALHA' }
+     $detail = if ($test.Status) { $test.Status } elseif ($test.Detail) { $test.Detail } else { '' }
+     $targetInfo = if ($test.Target) { " [$($test.Target)]" } else { '' }
+     $lines.Add(('  [{0}] {1}{2} - {3}' -f $status, $testName, $targetInfo, $detail))
+     if ($test.Recommendation) { $lines.Add(('        Dica: {0}' -f $test.Recommendation)) }
+     elseif ($test.Detail -and $test.Detail -ne $detail) { $lines.Add(('        {0}' -f $test.Detail)) }
+     if ($test.ErrorMessage) { $lines.Add(('        Erro: {0}' -f $test.ErrorMessage)) }
+ }
```

**Justificativa:**

- Elimina `InvokeMethodOnNull` ao testar `$null` antes de `.ToString()`.
- Compatível com contrato atual e defensivo contra ausência futura.
- `OverallStatus` derivado do `Summary` (Failed/Error → FALHA, Warning → AVISO, senão OK) — coerente com `Show-ConnectivityReport`.
- Itera `Results` (não `Tests`) e lê `TestName`/`Status`/`Recommendation`.

### 4.3 `xtudo.ps1:Invoke-XtudoScript` — hashtable splatting

**Arquivo:** `wba-windows-toolkit/xtudo.ps1:373-425`

Mantém a normalização existente (coberta por `tests/unit/Xtudo.Tests.ps1:41-46`) e acrescenta conversão para splatting correto:

```powershell
    $invokeArgs = @()
    if ($null -ne $Entry.PSObject.Properties['Args']) {
        foreach ($arg in @($Entry.Args)) {
            if ($null -eq $arg -or $arg -eq '') { continue }
            $text = [string]$arg
            if ($text -match '^\-\S+\s+\S+$' -and $text -notmatch '["'']') {
                $invokeArgs += @($text -split '\s+', 2)
                continue
            }
            $invokeArgs += $text
        }
    }

    # Converter lista flat (-Nome Valor) para splatting correto: hashtable para parametros nomeados,
    # array para posicionais. Array splatting direto com '-Nome' falha em ValidateSet (tratado como valor posicional).
    $htArgs = @{}
    $posArgs = @()
    for ($i = 0; $i -lt $invokeArgs.Count; $i++) {
        $tok = $invokeArgs[$i]
        if ($tok -match '^-([A-Za-z0-9_]+)$') {
            $pName = $Matches[1]
            if (($i + 1) -lt $invokeArgs.Count -and $invokeArgs[$i + 1] -notmatch '^-') {
                $htArgs[$pName] = $invokeArgs[$i + 1]
                $i++
            } else {
                $htArgs[$pName] = $true
            }
        } elseif ($tok -match '^-([A-Za-z0-9_]+):(.+)$') {
            $htArgs[$Matches[1]] = $Matches[2]
        } else {
            $posArgs += $tok
        }
    }

    if ($htArgs.Count -gt 0 -and $posArgs.Count -gt 0) {
        & $target @htArgs @posArgs
    } elseif ($htArgs.Count -gt 0) {
        & $target @htArgs
    } elseif ($posArgs.Count -gt 0) {
        & $target @posArgs
    } else {
        & $target
    }
```

**Justificativa:**

- Preserva o teste `Normaliza argumentos antes de chamar scripts`.
- Suporta `-Acao Diagnostico`, `-Modo Diagnostico`, switches (`-GerarHtml`) e valores com `:`.
- Reprodutor isolado confirma: `Test-Func @hash` e `& script.ps1 @hash` passam em `ValidateSet`, enquanto `@array` falha.

---

## 5. Validação

### 5.1 Reprodução isolada (Linux `pwsh 7.6.5`)

- `Get-ConnectivitySummary` com 15 `Success`: antes→`Success=1`; depois→`Success=15`.
- `Test-Func @('-Acao','Diagnostico')` → falha; `Test-Func @hash` → sucesso (ambos função e script).
- `testar-conectividade-internet.ps1` bloco TXT: antes `GeneratedAt.ToString()` null; depois sem exceção, usa `FinishedAt`.

### 5.2 Testes do repositório

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path tests/unit/Xtudo.Tests.ps1"
# Expected: 'Normaliza argumentos...' passa (mantém regex), demais asserts de catálogo OK

pwsh -NoProfile -Command "Invoke-Pester -Path tests/unit/WbaToolkit.Networking.Tests.ps1"
# Cobre ConvertFrom-IpRange, Invoke-ArpSweep etc. — não afetados
```

Recomendado execução completa em Windows antes de merge:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-Pester -Path tests/unit -Output Detailed
[System.Management.Automation.Language.Parser]::ParseFile('xtudo.ps1',[ref]$null,[ref]$null)
[System.Management.Automation.Language.Parser]::ParseFile('scripts/testar-conectividade-internet.ps1',[ref]$null,[ref]$null)
```

### 5.3 Checklist pós-correção (operador Windows)

1. `.\xtudo.ps1` → `7` (conectividade) deve listar `Sucesso:15` e gerar `conectividade-internet.txt` sem erro de método nulo.
2. `.\xtudo.ps1` → `10` (VSS) deve abrir modo Diagnóstico sem `ValidateSet`.
3. `.\xtudo.ps1` → `4` (gráfico) idem.
4. `.\xtudo.ps1 gerenciar copia sombra` e `.\xtudo.ps1 diagnosticar grafico` via CLI também.
5. Verificar `C:\WBA\Relatorios\conectividade-internet\...\conectividade-internet.json` contém `Summary.Success=15`.

---

## 6. Arquivos alterados

| Arquivo | Linhas | Tipo |
|---------|--------|------|
| `modules/WbaToolkit.Networking/Private/Get-ConnectivitySummary.ps1` | 8-25 | fix contagem |
| `scripts/testar-conectividade-internet.ps1` | 166-200 | alinhar contrato + null guard |
| `xtudo.ps1` | 373-425 | hashtable splatting |

Nenhum arquivo novo em produção; esta carta é documentação.

---

## 7. Riscos e próximos passos

- **Risco baixo:** `Get-ConnectivitySummary` mudança retrocompatível (estrutura idêntica, valores corretos).
- **Risco baixo:** `xtudo.ps1` fallback para `posArgs` garante scripts posicionais ainda funcionam.
- **Próximos:** Auditar demais wrappers em `scripts/` que possam replicar padrão TXT vs contrato (ex.: `sincronizar-relogio.ps1` já está correto). Criar teste unitário específico para `Get-ConnectivitySummary` com `GroupInfo.Count` e para `Invoke-XtudoScript` com `-Acao`/`-Modo` via Pester mock de script temporário.

---

## 8. Referências

- `wba-windows-toolkit/xtudo.ps1:49-268` catálogo, `360-391` Invite, `452-482` loop interativo
- `wba-windows-toolkit/scripts/testar-conectividade-internet.ps1:152-161` fluxo, `168-180` TXT
- `wba-windows-toolkit/modules/WbaToolkit.Networking/Public/Invoke-ConnectivityTest.ps1:99-109` contrato report
- `wba-windows-toolkit/modules/WbaToolkit.Networking/Public/Show-ConnectivityReport.ps1:30-50` uso correto
- `wba-windows-toolkit/modules/WbaToolkit.Networking/Private/New-ConnectivityResult.ps1:60-79` estrutura `Classification`
- `wba-windows-toolkit/modules/WbaToolkit.Networking/Private/Get-ConnectivitySummary.ps1:1-19` bug
- `tests/unit/Xtudo.Tests.ps1:41-46` teste de normalização preservado
- Transcrição original `FINANCEIRO04 2026-09-03` (anexada)

---

**Assinatura:** correção pronta para cherry-pick; validar em Windows elevado antes de publicar.

