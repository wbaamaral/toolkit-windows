# Tests

Diretorio reservado para testes automatizados do WBA Windows Toolkit.

Estrutura inicial recomendada:

```text
tests/
├── unit/
├── integration/
└── fixtures/
```

Regras:

- Os testes unitarios validam o contrato do `xtudo` como porta de entrada do operador.
- Os scripts oficiais em `scripts/` devem ser cobertos como implementacao do MVP.
- `experimental/` permanece como backlog e nao e a fonte ativa dos atalhos do operador.
- Testes de integracao devem ser separados e identificados.
- Funcoes reutilizaveis devem ser priorizadas para cobertura.
