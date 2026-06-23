# WBA Windows Toolkit

Toolkit PowerShell para suporte, diagnóstico, manutenção e automação de ambientes Windows.

O ponto de entrada recomendado é [`xtudo.ps1`](xtudo.ps1). Ele centraliza as ações mais usadas, aceita busca por
palavra-chave e reduz a necessidade de navegar pela árvore do projeto.

## Acesso rápido

- [Launcher principal](xtudo.ps1)
- [Catálogo de documentação](manuais/README.md)
- [Guia rápido do operador](manuais/operador/README.md)
- [Manual completo do operador](manuais/manual-operador-wba-windows-toolkit.md)
- [ADRs do projeto](docs/adr/README.md)

## O que existe no projeto

| Área | Conteúdo |
|---|---|
| `scripts/` | Rotas oficiais do operador e da linha atual |
| `modules/` | Funções reutilizáveis compartilhadas pelos scripts |
| `manuais/` | Guias do operador e documentação de referência |
| `docs/adr/` | Decisões arquiteturais e operacionais |
| `experimental/` | Ferramentas históricas ou ainda não promovidas |
| `tests/` | Testes unitários e laboratórios de validação |
| `tools/` | Apoio a releases e conferência do repositório |

## Rotas principais

- Limpar Windows
- Diagnosticar disco 100%
- Diagnosticar memória
- Diagnosticar gráfico
- Diagnosticar cliente AD
- Preparar imagem Windows
- Atualizar Windows

## Uso básico

```powershell
Set-Location C:\ti\wba-windows-toolkit
Set-ExecutionPolicy Bypass -Scope Process -Force
.\xtudo.ps1
```

## Regras operacionais

- Comece pelo diagnóstico antes de reparar.
- Use os scripts oficiais em `scripts/` para operação diária.
- Consulte `manuais/` quando precisar de roteiro ou referência.
- Mantenha `experimental/` fora do fluxo principal do operador.
- `-Help` e `Comment-Based Help` são obrigatórios na superfície oficial para consulta inline e documentação gerada.
- ADR 0021 registra o motivo dessa padronização.
- Rode os testes em `tests/unit` antes de publicar mudanças.

## Testes

```powershell
Invoke-Pester -Path tests/unit
```

## Publicação

Antes de publicar uma release, valide o pacote com:

```bash
bash tools/release-check.sh
```

## Licença

MIT. Consulte [`LICENSE`](LICENSE) para os termos completos.
