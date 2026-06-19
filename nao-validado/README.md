# Scripts NÃO validados operacionalmente

> **Aviso:** os scripts listados aqui **não têm execução real documentada em Windows**.
> **Não são recomendados para uso em produção** até validação operacional.
> Eles permanecem em seus diretórios originais (continuam funcionando); este registro
> apenas os **identifica**. Cada um tem um banner `[NAO VALIDADO]` no topo do arquivo.

Critério de "validado": execução real em Windows (PowerShell 5.1 e/ou 7) com evidência
registrada em `spec-win-toolkit/spec/IMPLEMENTADO.md`. Apenas sintaxe (Parser), carga de
módulo, BOM (ADR 0007) ou testes Pester **não** contam como validação operacional.

## Não validados (10)

| Script | Diretório | Por que não validado |
|---|---|---|
| `Diagnostico-GPO-Client.ps1` | active-directory/ | exige domínio AD; nunca executado (ver `tests/lab-ad/`) |
| `Testa-Repara-ContaMaquinaAD.ps1` | active-directory/ | exige domínio AD; nunca executado |
| `Configurar-Idioma-Regional.ps1` | configuration/ | sem execução real; altera idioma/regional do SO |
| `Diagnostico-Driver-Grafico.ps1` | diagnostics/ | sem execução real |
| `Verificar-Atualizacoes-Hardware.ps1` | diagnostics/ | sem execução real (somente leitura) |
| `Testar-Conectividade-Internet.ps1` | diagnostics/networking/ | sem execução real |
| `Backup-Restaurar-Drivers.ps1` | maintenance/ | sem execução real; usa DISM/pnputil |
| `Limpeza-WinSxS.ps1` | maintenance/ | sem execução real; usa DISM no Component Store |
| `Preparar-Imagem-Windows.ps1` | maintenance/ | sem execução real; sysprep (alto risco) |
| `Remover-Perfis-Inativos.ps1` | utilities/ | sem execução real; remove perfis de usuário (alto risco) |

## Já validados por execução real (não estão aqui)

`upgrade-windows.ps1`, `Diagnostico-Memoria.ps1`, `Gerenciar-Inicializacao-Windows.ps1`,
`Diagnostico-Reparo-HD100.ps1`, `Inventario-Hardware-Software.ps1`, `limpeza-windows.ps1`,
`Analise-Espaco-Disco.ps1`.

## Como um script sai desta lista

1. Executar o script em Windows real (5.1 e/ou 7) e registrar a evidência em `IMPLEMENTADO.md`.
2. Remover o banner `[NAO VALIDADO]` do topo do arquivo.
3. Remover a linha correspondente da tabela acima.

> Prioridade natural de validação: os scripts de AD (`Diagnostico-GPO-Client`,
> `Testa-Repara-ContaMaquinaAD`) já têm lab pronto em `tests/lab-ad/`.

## Histórico de validação

- 2026-06-19: `Analise-Espaco-Disco.ps1` validado em Windows real (PS 5.1, VM de testes) — varredura de
  C: (122.713 pastas / 372.171 arquivos), totalizadores de volume corretos (Total 127,17 GB · Usado 35,08 GB
  / 28% · Livre 92,09 GB), confirmando a correção do `DriveInfo.TotalSize`/`TotalFreeSpace`.
