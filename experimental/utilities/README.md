# utilities

Scripts utilitários de uso geral para administração do dia a dia. Ferramentas avulsas que não se encaixam em categorias específicas, mas são frequentemente necessárias em suporte técnico, implantação e automação de tarefas rotineiras.

---

## Scripts

### `Remover-Perfis-Inativos.ps1`

**Função:** Lista todos os perfis de usuário locais com espaço em disco e permite remover interativamente perfis antigos ou inativos.

**Principais ações:**

| Etapa | Ação |
|---|---|
| Coleta | Enumera perfis via `Win32_UserProfile` (exclui perfis de sistema automaticamente) |
| Tamanho | Calcula o espaço em disco de cada perfil |
| Classificação | Classifica cada perfil: **Ativo**, **Recente**, **Inativo**, **Sem conta** (SID órfão) ou **Carregado** (sessão ativa) |
| Apresentação | Exibe tabela interativa com seleção, total de espaço e preview do espaço recuperável |
| Seleção | Individual por número (`1 3 5`), em massa (`a` = todos os elegíveis) ou limpeza (`c`) |
| Detalhes | Comando `i <n>` exibe SID, caminho completo, último acesso, dias inativo e status |
| Remoção | Confirmação obrigatória antes de excluir; usa `Remove-CimInstance Win32_UserProfile` (remove pasta + chave de registro) |
| Modo silencioso | Auto-seleciona e remove perfis órfãos + inativos sem interação |
| Simulação | `-DryRun` mostra o que seria feito sem alterar o sistema |

**Parâmetros:**

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `-InactiveDays` | `90` | Dias sem acesso para considerar o perfil inativo |
| `-Silent` | — | Remove automaticamente órfãos + inativos sem prompts |
| `-DryRun` | — | Simula a remoção sem alterar nada |
| `-ExcludeProfile` | — | Nomes de perfis a ignorar na listagem |
| `-NoLog` | — | Não cria arquivo de log |

**Uso básico:**

```powershell
# Interface interativa (padrão)
.\Remover-Perfis-Inativos.ps1

# Simulação sem remover nada
.\Remover-Perfis-Inativos.ps1 -DryRun

# Remoção automática de órfãos + inativos há mais de 90 dias
.\Remover-Perfis-Inativos.ps1 -Silent

# Alterar limiar para 180 dias e excluir conta de serviço
.\Remover-Perfis-Inativos.ps1 -InactiveDays 180 -ExcludeProfile "svc.backup"
```

**Requisitos:** Administrador local. Windows 10+. PowerShell 5.1+.

**Log:** `C:\WBA\Relatorios\Utilities\<timestamp>\logs\<timestamp>-Remover-Perfis-Inativos.log` ou `<DiretorioSaida>\Utilities\<timestamp>\logs\...`

---

---

### `Analise-Espaco-Disco.ps1`

**Função:** Varre os discos locais em busca de espaço desperdicado, gera relatório no estilo Baobab/Disk Usage Analyzer com Top 20 pastas e Top 10 arquivos. Operação **estritamente de leitura** — nenhuma alteração é realizada.

**Principais ações:**

| Etapa | Ação |
|---|---|
| Varredura | Percorre todos os volumes fixos (ou drive especificado) usando `System.IO` de alto desempenho |
| Agregação | Calcula tamanho total de cada pasta incluindo subpastas (bottom-up aggregation) |
| Pontos de reparse | Ignora junctions e links simbólicos para evitar loops e dupla contagem |
| Ocultos/Sistema | Detecta atributos Hidden e System e pontua no relatório |
| Desperdício | Estima espaço em 15 categorias conhecidas: temp, cache, dumps, Windows.old, lixeira, browsers, WinSxS, etc. |
| Console | Exibe Top 20 pastas e Top 10 arquivos com barras ASCII proporcionais e código de cores |
| HTML | Gera relatório com tabelas, barras de uso por volume e estimativa de limpeza |
| PDF | Converte HTML para PDF via Chrome ou Edge headless (quando disponível) |

**Parâmetros:**

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `-Drive` | todos os fixos | Letra(s) do volume a varrer (ex: `C`, `C,D`) |
| `-OutputDir` | `ReportsRoot` ou `C:\WBA\Relatorios` | Raiz de relatórios; o script cria `Utilities\<timestamp>` |
| `-NaoPDF` | — | Gera apenas HTML, sem conversão para PDF |
| `-Silent` | — | Sem progresso no console durante a varredura |

**Uso básico:**

```powershell
# Varrer todos os volumes locais
.\Analise-Espaco-Disco.ps1

# Varrer apenas C: e salvar em D:\Relatorios
.\Analise-Espaco-Disco.ps1 -Drive C -OutputDir "D:\Relatorios"

# Apenas HTML, sem PDF
.\Analise-Espaco-Disco.ps1 -NaoPDF

# Múltiplos volumes, modo silencioso
.\Analise-Espaco-Disco.ps1 -Drive C,D -Silent
```

**Requisitos:** Administrador local (para acessar pastas protegidas do sistema). Windows 10+. PowerShell 5.1+.

**Saída:** `C:\WBA\Relatorios\Utilities\<timestamp>\` ou `<OutputDir>\Utilities\<timestamp>\`

**Log:** `C:\WBA\Relatorios\Utilities\<timestamp>\logs\<timestamp>-Analise-Espaco-Disco.log`

---

> **Outros scripts planejados para este diretório:**
> - Coleta de informações rápidas do sistema (versão, hostname, IP)
> - Geração de senha segura aleatória
> - Verificação e renovação de certificados locais
