# Scripts NÃO validados operacionalmente

> **Aviso:** os scripts listados aqui ainda carregam o banner `[NAO VALIDADO]` no topo do arquivo
> porque **não têm execução real de ponta a ponta documentada** no fluxo crítico em Windows.
> **Não são recomendados para uso em produção** sem validação prévia. Eles já vivem em `scripts/`
> (continuam funcionando); este registro apenas os **identifica**.

Critério de "validado": execução real em Windows (PowerShell 5.1 e/ou 7) com evidência registrada
em `spec-win-toolkit/spec/IMPLEMENTADO.md`. Apenas sintaxe (Parser), carga de módulo, BOM (ADR 0007)
ou testes Pester **não** contam como validação operacional.

## Ainda com banner `[NAO VALIDADO]` (5)

| Script | Por que não validado |
|---|---|
| `scripts/diagnosticar-grafico.ps1` | diagnóstico de driver gráfico; aguarda validação do fluxo completo |
| `scripts/verificar-atualizacoes-hardware.ps1` | consulta BIOS/drivers via Windows Update; aguarda validação |
| `scripts/testar-conectividade-internet.ps1` | invólucro do módulo Networking; aguarda validação do fluxo completo |
| `scripts/limpar-winsxs.ps1` | usa DISM no Component Store; modo Limpeza não validado em produção |
| `scripts/preparar-imagem-windows.ps1` | sysprep (alto risco, irreversível); não executado de ponta a ponta |

## Já validados por execução real (sem banner)

`configurar-idioma-regional.ps1`, `gerenciar-drivers.ps1`, `gerenciar-inicializacao.ps1`,
`analisar-espaco-disco.ps1`, `remover-perfis-inativos.ps1`, `gerenciar-login-automatico.ps1`,
`inventario-hardware-software.ps1`, `diagnosticar-disco-100.ps1`, `diagnosticar-memoria.ps1`,
`atualizar-windows.ps1`, `limpar-windows.ps1`, `diagnosticar-ad-cliente.ps1`.

> Os antigos `Diagnostico-GPO-Client.ps1` e `Testa-Repara-ContaMaquinaAD.ps1` foram **consolidados**
> em `scripts/diagnosticar-ad-cliente.ps1` (diagnóstico + reparo guiado de canal seguro/hora).

## Como um script sai desta lista

1. Executar o script em Windows real (5.1 e/ou 7) e registrar a evidência em `IMPLEMENTADO.md`.
2. Remover o banner `[NAO VALIDADO]` do topo do arquivo.
3. Remover a linha correspondente da tabela acima.
