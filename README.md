# WBA Windows Toolkit

Toolkit PowerShell para diagnóstico, manutenção e suporte a ambientes Windows.

## Comece aqui

A documentação operacional está em [`docs/README.md`](docs/README.md). Ela reúne os procedimentos, comandos,
cuidados e locais de saída que o operador precisa consultar.

Para abrir o menu interativo:

```powershell
Set-Location C:\ti\wba-windows-toolkit
Set-ExecutionPolicy Bypass -Scope Process -Force
.\xtudo.ps1
```

O `Xtudo` é o ponto de entrada recomendado para as ações mais comuns. Quando a tarefa não estiver no menu, use o
script correspondente em `scripts/` e consulte `-Help`.

## Desenvolvimento

Os módulos reutilizáveis ficam em `modules/`, os testes em `tests/` e os recursos de apoio em `tools/`.

Execute a suíte antes de publicar alterações:

```powershell
Invoke-Pester -Path tests/unit
```

Para gerar a documentação HTML local no Windows PowerShell 5.1:

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
Export-ToolkitDocumentation -Mode All -Force
```

O resultado fica em `docs/portal/`.

## Estrutura essencial

| Caminho | Uso |
|---|---|
| `xtudo.ps1` | Menu interativo do operador |
| `scripts/` | Scripts oficiais de operação |
| `modules/` | Funções reutilizáveis |
| `docs/` | Documentação operacional, referência técnica e geração do PDF |
| `tests/` | Testes unitários e de integração |
| `experimental/` | Material não promovido para operação |

As especificações, decisões arquiteturais e histórico de desenvolvimento ficam no repositório `spec-win-toolkit`.

## Licença

MIT. Consulte [`LICENSE`](LICENSE).
