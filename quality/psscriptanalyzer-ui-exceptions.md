# Exceções de UI do PSScriptAnalyzer

Rastreio: **BCK-058**. A baseline em `psscriptanalyzer-baseline.json` é o
limite máximo por regra e arquivo; reduções são aceitas, aumentos ou entradas
novas falham no teste automatizado.

`PSAvoidUsingWriteHost` permanece somente onde `Write-Host` é apresentação ao
operador, e não feedback semântico:

- bootstrap antes de o `WbaToolkit.Core` poder ser carregado;
- títulos, separadores, tabelas, menus e prompts interativos (TUI);
- relatórios de console cujo conteúdo é deliberadamente formatado por cor ou
  alinhamento.

Mensagens de estado (erro, aviso, sucesso, progresso e dry-run) devem usar os
wrappers do Core. `SharedCoreUsage.Tests.ps1` mantém a allowlist mínima de
mensagens semânticas temporariamente inevitáveis e falha se aparecer outro uso
sem justificativa. Cada lote de remoção reduz a baseline sem atualizá-la para
ocultar o ganho.
