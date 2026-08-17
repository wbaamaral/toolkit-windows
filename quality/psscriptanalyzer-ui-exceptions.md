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

## BCK-060 — `auditar-arquivos-dropbox.ps1` e `diagnosticar-dropbox.ps1`

Os dois scripts novos do diagnóstico/auditoria de Dropbox seguem o mesmo padrão
já estabelecido em `detectar-ip-duplicado.ps1` e `diagnosticar-ad-cliente.ps1`:
`Write-Host` aparece apenas em `Show-Help` (texto puro), no bootstrap antes do
`WbaToolkit.Core` estar disponível (mensagens `[FALHA] Modulo nao encontrado`/
`Nao foi possivel carregar`, já cobertas pela allowlist de
`SharedCoreUsage.Tests.ps1`), no menu de seleção de pasta Dropbox quando há mais
de uma conta detectada, e em separadores de linha em branco. Nenhuma mensagem de
status semântico (sucesso/erro/aviso) usa `Write-Host` — todas passam por
`Write-Ok`/`Write-Fail`/`Write-Warn`/`Write-Info`. Baseline atualizada de forma
puramente aditiva (sem alterar entradas existentes de outros arquivos).
