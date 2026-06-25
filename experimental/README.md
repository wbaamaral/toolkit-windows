# Experimental

Área de suporte para material que ainda não faz parte da linha principal do MVP.

Conteúdo colocado aqui permanece versionado, mas **não é** o ponto de entrada do operador.

Atualmente esta pasta está praticamente vazia: todos os scripts operacionais já foram promovidos
para `scripts/` (ADR 0022). Resta apenas o registro de scripts ainda não validados operacionalmente.

## Estrutura

```text
experimental/
└── nao-validado/
```

## Onde fica cada coisa

- Atalhos/scripts do operador: `scripts/` (via launcher `Xtudo`).
- Módulos reutilizáveis: `modules/`.
- Manuais do operador: `manuais/`.
- Arquivos `.reg` de sysprep: `regfiles/sysprep/` (na raiz do repositório).

Se uma ferramenta nova ainda não fizer parte do fluxo oficial do operador, ela pode ser
desenvolvida aqui até ser promovida para `scripts/`.
