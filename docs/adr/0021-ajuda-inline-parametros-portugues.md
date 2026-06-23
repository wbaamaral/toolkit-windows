# ADR 0021: Ajuda inline obrigatória e preferência por parâmetros curtos em português

## Status

Aceita

## Contexto

O `WBA Windows Toolkit` foi desenhado para uso operacional por técnicos e operadores que precisam localizar funções
e executar scripts com o menor atrito possível.

Na prática, o projeto passou a depender de duas formas de consulta:

- `-Help` em scripts operacionais da superfície oficial, para exibir uso rápido no próprio ponto de entrada.
- `Comment-Based Help` em funções públicas, para integração com `Get-Help` e com o gerador de documentação HTML.

Além disso, a experiência de uso melhora quando o operador encontra parâmetros curtos, legíveis e em português, com
nome compatível com a ação executada. Isso reduz memorização, aumenta descoberta e combina melhor com a interface do
`Xtudo`.

## Decisão

Adota-se a seguinte regra para a superfície oficial do toolkit:

- todo script oficial deve expor `-Help` e responder com ajuda inline de uso;
- toda função pública deve manter `Comment-Based Help` completo e compatível com `Get-Help`;
- parâmetros curtos em português são preferenciais quando isso não conflitar com compatibilidade, sem obrigatoriedade
  absoluta de encurtamento;
- o nome do parâmetro deve refletir com clareza a ação que ele executa;
- parâmetros consagrados do ecossistema PowerShell podem ser mantidos quando fizerem sentido operacional, como `-Path`,
  `-Force`, `-Verbose` e `-WhatIf`.

## Consequências

Positivas:

- o operador consulta o script sem sair do fluxo;
- a documentação gerada por `Get-Help` e pelo portal HTML permanece consistente;
- o catálogo do `Xtudo` fica mais fácil de operar e de ensinar.

Custos:

- scripts oficiais passam a exigir padronização de ajuda, mesmo em alterações pequenas;
- funções públicas sem CBH deixam de ser aceitáveis na superfície oficial;
- testes e revisão precisam verificar a presença de `-Help` e da documentação embutida.

## Referências

- [README do projeto](../../README.md)
- [Scripts](../../scripts/README.md)
- [Módulos](../../modules/README.md)
- [Manual do operador](../../manuais/manual-operador-wba-windows-toolkit.md)
