# Scripts

Camada plana de entrada operacional do `Xtudo`.

Cada arquivo aqui usa um nome verbal curto (verbo-objeto, ADR 0022) e contém o fluxo
operacional atual do MVP. Todos os scripts operacionais já vivem aqui em `scripts/`;
`experimental/` mantém apenas o registro de não-validados e material futuro ainda não pronto.

Regra prática:

- operador entra por `.\xtudo.ps1`
- scripts em `scripts/` são a superfície oficial do MVP
- `experimental/nao-validado/` registra scripts ainda sem validação operacional
- parâmetros não precisam ser curtos por obrigação; prefira nomes em português, curtos e com sentido direto do que o parâmetro faz
- mantenha `Comment-Based Help` para explicar nome, uso e efeito de cada parâmetro público
- `-Help` é obrigatório em todos os scripts da superfície oficial e deve exibir a consulta inline de uso
- ver ADR-0026 (repositório `spec-win-toolkit`) para o racional dessa padronização

Exemplos:

```powershell
.\xtudo.ps1
.\scripts\limpar-windows.ps1
.\scripts\diagnosticar-memoria.ps1
.\scripts\atualizar-windows.ps1
.\scripts\diagnosticar-ad-cliente.ps1
```

## Dropbox

### `diagnosticar-dropbox.ps1`

**Função:** Diagnóstico de saúde do cliente Dropbox — processo, instalação, disco, arquivos
problemáticos, frescor de pastas, conectividade, proxy, Defender e hora. Score 0–100.

**Saída:** TXT, HTML (`-GerarHtml`), JSON (`-ExportarJson`).

**Exemplos:**

```powershell
.\scripts\diagnosticar-dropbox.ps1
.\scripts\diagnosticar-dropbox.ps1 -ExportarJson
.\scripts\diagnosticar-dropbox.ps1 -GerarHtml -AbrirRelatorio
.\scripts\diagnosticar-dropbox.ps1 -Modo Assistido -ReiniciarProcesso -ExcluirDoDefender
.\scripts\diagnosticar-dropbox.ps1 -Path 'D:\Dropbox' -ExportarJson -DiretorioSaida 'C:\Temp'
```

### `auditar-arquivos-dropbox.ps1`

**Função:** Auditoria e classificação de arquivos do Dropbox via atributos NTFS / Cloud Files.
Identifica estados: SomenteNuvem, LocalENuvem, SomenteLocal, Indeterminado.

**Exemplos:**

```powershell
.\scripts\auditar-arquivos-dropbox.ps1
.\scripts\auditar-arquivos-dropbox.ps1 -Report CloudOnly
.\scripts\auditar-arquivos-dropbox.ps1 -NonInteractive -Path 'D:\Dropbox' -Report All -Output '.\auditoria.csv'
```

### `corrigir-arquivos-dropbox.ps1`

**Função:** Correção em massa de arquivos problemáticos do Dropbox identificados pelo diagnóstico.
Modos: Renomeação (ajusta nome do arquivo) ou Mudança de Localização (move para pasta simplificada).

**Entrada:** JSON gerado pelo `diagnosticar-dropbox.ps1 -ExportarJson`.

**Saída:** `alteracoes.json`, `erros.json`, `rollback.json` e `simulacao.json` (modo `-Simular`).

**Exemplos:**

```powershell
.\scripts\corrigir-arquivos-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json' -Simular
.\scripts\corrigir-arquivos-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'
.\scripts\corrigir-arquivos-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json' -Correcao MudancaLocalizacao
```

### `normalizar-dropbox.ps1`

**Função:** Ferramenta completa de normalização com fluxo iterativo controlado.
Implementa TUI interativa para seleção/edição de propostas, validação via HTML
e aplicação controlada com relatório detalhado de → para.

**Modos:**
- `TUI` (padrão): interface interativa para selecionar/editar propostas
- `Proposta`: gera proposta sem interação (todos selecionados)
- `Aplicar`: aplica proposta após validação
- `Relatorio`: gera relatório HTML detalhado

**Entrada:** JSON gerado pelo `diagnosticar-dropbox.ps1 -ExportarJson`.

**Saída:** `correcoes-propostas.json`, `correcoes-propostas.html`,
`correcoes-aplicadas.json`, `correcoes-aplicadas.html`.

**Exemplos:**

```powershell
.\scripts\normalizar-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json'
.\scripts\normalizar-dropbox.ps1 -InputFile '.\diagnostico-dropbox.json' -Modo Proposta -NonInteractive
.\scripts\normalizar-dropbox.ps1 -Modo Aplicar -PropostaFile '.\correcoes-propostas.json'
.\scripts\normalizar-dropbox.ps1 -Modo Relatorio -PropostaFile '.\correcoes-propostas.json'
.\scripts\normalizar-dropbox.ps1 -Modo Relatorio -ResultadoFile '.\correcoes-aplicadas.json'
```

## Inventário

### `inventario-hardware-software.ps1`

**Função:** Gera inventário completo de hardware e software em relatório HTML com conversão opcional para PDF.

**Dependência de módulo:** `WbaToolkit.Inventory` para o mapa de cobertura do escopo e evolução futura do inventário.

**Cobertura atual:**

- sistema operacional;
- processador;
- memória RAM;
- placa-mãe e BIOS;
- armazenamento;
- placa de vídeo;
- rede;
- monitores;
- software instalado;
- atualizações / hotfixes;
- serviços;
- resumo de hardware e drivers em saída enxuta opcional.

**Ainda não coberto como rotina separada:**

- inventário de Active Directory do cliente;
- inventário de impressoras e periféricos dedicados;
- inventário de rede por topologia, VLAN ou switch;
- inventário de usuários, perfis e sessões locais;
- inventário patrimonial/CMDB.

**Exemplos:**

```powershell
.\scripts\inventario-hardware-software.ps1
.\scripts\inventario-hardware-software.ps1 -NaoPDF
.\scripts\inventario-hardware-software.ps1 -GerarResumoHardwareDrivers
.\scripts\inventario-hardware-software.ps1 -SomenteHardwareDrivers
```
