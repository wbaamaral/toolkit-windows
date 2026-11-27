# Diretrizes para Agentes de IA — `wba-windows-toolkit`

Regras para qualquer agente de IA ou assistente autônomo operando neste repositório.

---

## Especificações (`spec/`) — onde ficam e como buscar

As especificações (ADRs, backlog, padrões de qualidade, processo de release, estado) ficam num **repositório
separado** e **não** fazem parte do repositório de código.

| Item | Valor |
|---|---|
| Repositório | `spec-win-toolkit` (Gitea interno, acesso só pela rede interna) |
| Clone (SSH) | `ssh://git@192.168.5.235:2222/wbaamaral/spec-win-toolkit.git` |
| Web | `http://192.168.5.235:3000/wbaamaral/spec-win-toolkit` |
| Branch | `main` |
| Lugar na base de código | pasta **`spec/` na raiz** deste repositório, com `.git` próprio |

A pasta `spec/` está no `.gitignore` do repositório de código. Por isso ela não vem no clone e nunca é commitada
nele. Ferramentas e regras deste repo (como `spec/qualidade/...`) esperam encontrar a pasta exatamente nesse
caminho.

**Buscar pela primeira vez** (a partir da raiz do repositório de código):

```powershell
git clone ssh://git@192.168.5.235:2222/wbaamaral/spec-win-toolkit.git spec
```

**Atualizar** antes de consultar ou alterar:

```powershell
git -C spec pull --ff-only
```

**Conferir** se está no lugar certo: `git -C spec remote get-url origin` deve mostrar a URL acima, e
`git check-ignore spec` deve confirmar que a pasta é ignorada pelo repo de código.

Regras:

- Commits e pushes do spec são feitos **dentro de `spec/`** (`git -C spec ...`), com o mesmo padrão de commit
  (seção 0.2).
- O spec é publicado **somente** no Gitea interno. Nunca envie para o GitHub ou o Codeberg, e nunca copie
  arquivos do spec para o repositório de código.
- Pontos de entrada úteis: `spec/README.md`, `spec/STATUS.md`, `spec/BACKLOG.md`, `spec/adr/`,
  `spec/qualidade/processo-release.md`.

---

## Acompanhamento de desenvolvimento — tudo é registrado no `spec/`

Os marcos, as alterações e os desenvolvimentos do toolkit são **registrados e acompanhados no `spec/`**, não no
repositório de código. Nenhuma alteração relevante de código começa, termina ou é declarada validada sem o
registro correspondente no `spec/`. A regra vem da ADR 0014 e de `spec/qualidade/padrao-quadro-operacional.md`.

### Onde está cada coisa

| Arquivo / pasta | Para que serve |
|---|---|
| `estado/manifesto-estado.yml` | **Fonte canônica** do estado corrente: cada item com `id`, `estado`, `prioridade`, `responsavel`, `inicio`, `branch` e `resumo` |
| `STATUS.md` | Resumo executivo do projeto, com a situação por área e por frente funcional |
| `EM-DESENVOLVIMENTO.md` | O que está em andamento agora: ID, responsável, data, branch e próxima ação |
| `BACKLOG.md` | Itens aprovados ou candidatos que ainda não começaram (`BCK-NNN`), por prioridade |
| `IMPLEMENTADO.md` | Entregas concluídas, com commits e **evidência de validação** (testes, execução real em Windows) |
| `BLOQUEIOS.md` | Impedimentos (`BLQ-NNN`) com item relacionado, impacto e responsável; o histórico é mantido |
| `ROADMAP.md`, `ideias/` | Intenções futuras. Não é trabalho ativo |
| `estado/matriz-rastreabilidade.md` | Liga requisito ou ADR → código → teste/evidência → lacuna (`RT-NNN`) |
| `tarefas/` | Plano detalhado de cada frente maior (ex.: `code-review-2026-11-25.md`, que fatia o BCK-062 a BCK-066) |
| `adr/` | Decisões de arquitetura numeradas (`NNNN-titulo.md`). Mudança arquitetural exige ADR |
| `modulos/`, `arquitetura/`, `qualidade/`, `seguranca/` | Requisitos por módulo, arquitetura e padrões obrigatórios |
| `templates/` | Modelos de item operacional, bloqueio, commit, entrada de changelog e outros |

### Identificadores

- `BCK-NNN`: item de trabalho, que nasce no backlog e mantém o ID até o fim.
- `DEV-NNN`: registros de desenvolvimento e validação em `IMPLEMENTADO.md` (série histórica).
- `BLQ-NNN`: bloqueio. `RT-NNN`: linha da matriz de rastreabilidade. `NNNN`: número de ADR.
- O ID do item aparece no resumo dos commits do código, por exemplo `fix(rede): ... (BCK-065)`.

### Ciclo de vida de um item

```text
ideia/ROADMAP ─► BACKLOG.md (BCK-NNN) ─► EM-DESENVOLVIMENTO.md ─► IMPLEMENTADO.md
                                                │
                                                └─► BLOQUEIOS.md (BLQ-NNN), se travar
```

Estados permitidos no manifesto: `ideia`, `em-analise`, `especificando`, `especificado`, `em-desenvolvimento`,
`em-teste`, `aguardando-validacao`, `implementado-parcial`, `implementado`, `validado`, `bloqueado`,
`cancelado` e `descontinuado`.

### O que o agente deve fazer

1. **Antes de começar**, faça `git -C spec pull --ff-only` e consulte nesta ordem: `EM-DESENVOLVIMENTO.md`,
   `BACKLOG.md`, `IMPLEMENTADO.md`, `BLOQUEIOS.md` e `estado/manifesto-estado.yml`. Assim você evita trabalho
   duplicado ou que conflite com algo em andamento.
2. **Ao assumir um item**, mova-o do backlog para `EM-DESENVOLVIMENTO.md`, com responsável, data, branch e
   próxima ação, e atualize o mesmo item no manifesto. Um item fica em **um único estado por vez**.
3. **Frente grande** ganha plano em `tarefas/`, fatiado em itens `BCK`. **Decisão de arquitetura** ganha ADR
   nova em `adr/`.
4. **Durante o trabalho**, atualize a próxima ação e o progresso. Se travar, registre em `BLOQUEIOS.md`.
5. **Ao concluir**, mova o resumo para `IMPLEMENTADO.md` com os commits e a evidência. Atualize o manifesto, a
   matriz (quando houver requisito ou ADR envolvido) e o `STATUS.md` se o resumo executivo mudar.
6. **Nunca** declare `validado` sem evidência verificável (suíte Pester, execução real em Windows PowerShell 5.1
   e afins). Sem execução real documentada, o estado é `implementado-parcial`.
7. **Divergência** entre um quadro Markdown e o manifesto: não decida pelo texto histórico. Registre na matriz,
   corrija o manifesto com evidência e reconcilie o quadro na mesma mudança.
8. **Faça o commit das atualizações do `spec/` no repositório do spec** (`git -C spec commit ...`), separado do
   commit de código e com o mesmo padrão de mensagem.

Validação automática do quadro (IDs duplicados, item em dois estados, campos e estados inválidos):

```powershell
python spec/tools/wba-validar-quadro.py      # requer Python 3 + PyYAML (pip install pyyaml)
python spec/tools/wba-gerar-painel.py painel.html
```

No Windows, chame `python`, não `python3`: o `python3` cai no atalho da Microsoft Store. Defina
`$env:PYTHONUTF8 = '1'` se a saída sair com acentos quebrados. Não use `python -I`, porque essa opção ignora o
PyYAML instalado com `pip install --user`.

---

## 0. Publicação nos repositórios — leia antes de qualquer `git push`

### 0.1. Mapa dos repositórios

O código e as especificações são **dois repositórios git separados**. Nunca misture conteúdo de um no outro.

| Repositório | Diretório local | Remoto | URL | Papel |
|---|---|---|---|---|
| Código | raiz do repo | `origin` | `ssh://git@192.168.5.235:2222/wbaamaral/wba-windows-toolkit.git` | Gitea interno (trabalho diário) |
| Código | raiz do repo | `github` | `git@github.com:wbaamaral/toolkit-windows.git` | Espelho público |
| Código | raiz do repo | `codeberg` | `git@codeberg.org:wbaamaral/wba-windows-toolkit.git` | Espelho público |
| Especificações | `spec/` (`.git` próprio, ignorado pelo repo de código) | `origin` | `ssh://git@192.168.5.235:2222/wbaamaral/spec-win-toolkit.git` | Somente Gitea interno, **nunca** publicar nos espelhos |

Se `github` ou `codeberg` não existirem no clone, o `tools/publish-release.ps1` cria esses remotos, ou crie à mão:

```powershell
git remote add github   git@github.com:wbaamaral/toolkit-windows.git
git remote add codeberg git@codeberg.org:wbaamaral/wba-windows-toolkit.git
```

### 0.2. Regras

- **Push só quando o usuário pedir**, e só para o destino que ele pediu.
- **Antes de enviar**, confira se o remoto está contido no local (nada de push forçado):
  `git fetch <remoto>` e depois `git merge-base --is-ancestor <remoto>/main main`.
  As tags remotas devem apontar para os mesmos commits das tags locais.
- **Nunca** use `--force` nem reescreva tags já publicadas.
- Commits seguem `spec/qualidade/padrao-commits-e-supervisor-tecnico.md` (ADR 0015): `tipo(escopo): resumo`,
  seções Contexto/Alterações/Validação e trailer `Supervisor:`. **Proibido** trailer que identifique IA ou ferramenta.
- A identidade git do repositório já está configurada. Não altere `user.name`/`user.email`.

### 0.3. Sincronizar commits e tags (somente SSH, sem token)

```powershell
git push origin main;   git push origin --tags
git push github main;   git push github --tags
git push codeberg main; git push codeberg --tags
```

Isso **não** cria as páginas de release. Para elas, veja a seção 0.4.

### 0.4. Publicar uma release (tag + página de release)

Use `tools/publish-release.ps1` (Windows PowerShell 5.1+). Ele publica o código no GitHub e no Codeberg, e o spec
no Gitea:

```powershell
# 1. Tokens (somente na sessão; nunca versionar)
gh auth login                                # ou: $env:GITHUB_TOKEN = '<token>'
$env:CODEBERG_TOKEN = '<token>'              # Codeberg: escopo write:repository
$env:GITEA_TOKEN    = '<token>'              # só se publicar o spec

# 2. Conferir sempre com -DryRun antes
.\tools\publish-release.ps1 -CodeVersion v2.0.4 -SpecVersion v1.3.0 -DryRun

# 3. Publicar
.\tools\publish-release.ps1 -CodeVersion v2.0.4 -SpecVersion v1.3.0
```

Opções úteis: `-Target GitHub` ou `-Target Codeberg` (só um espelho), `-SkipSpec` (só o código),
`-Description '<texto>'` (atualiza a descrição dos espelhos) e `-Force` (sem confirmação interativa).

Pré-requisitos da versão:

- `RELEASE-NOTES.md` (corpo da release) e `CHANGELOG.md` atualizados para a nova versão e commitados.
- Se a tag já existir e não apontar para o `HEAD`, o script para. Escolha outra versão; não mova a tag.
- O processo formal está em `spec/qualidade/processo-release.md` (ADR 0018).

Os scripts `.sh` em `tools/` (`publish-release.sh`, `publish-codeberg-release.sh`, `publish-all-releases.sh`) são
a versão Linux antiga, que publica só no Codeberg. No Windows, use o `.ps1`.

### 0.5. Objetos Git LFS e push de tags antigas

Tags antigas referenciam versões antigas dos PDFs em LFS (`docs/` e `manuais/`). Um clone comum baixa só os
objetos do checkout atual. Por isso, enviar todas as tags a partir dele falha com
`Git LFS upload failed ... (missing)`, porque faltam localmente os objetos das tags antigas.

**Desde 2026-11-27 o Gitea tem todos os 14 objetos LFS do histórico.** Quatro deles faltavam no Gitea e
respondiam 404; eles foram recuperados do Codeberg e enviados com `git lfs push origin --all`. A conferência foi
feita com um clone vazio que baixou tudo sem erro. Os três remotos estão completos.

Se o push das tags falhar por objeto ausente, baixe todos os objetos do Gitea e repita o push:

```powershell
git lfs fetch origin --all
```

Se o Gitea voltar a responder 404 para algum objeto, use o Codeberg como fonte e depois complete o Gitea:

```powershell
git lfs fetch https://codeberg.org/wbaamaral/wba-windows-toolkit.git --all
git lfs push origin --all
```

Nunca contorne com `lfs.allowincompletepush`.

### 0.6. Acesso SSH

A chave `~/.ssh/id_ed25519` está cadastrada no GitHub e no Codeberg. Para testar o acesso:

```powershell
ssh -T git@github.com
ssh -T git@codeberg.org
```

Se aparecer `Host key verification failed`, adicione a chave do host somente depois de conferir a fingerprint
publicada pelo serviço:

- GitHub: `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`
- Codeberg: `SHA256:mIlxA9k46MmM6qdJOdMnAQpzGxF4WIVVL+fj+wZbw0g`

---

## 1. Segurança

- Nunca versionar tokens, senhas ou chaves. Tokens de publicação ficam só em variáveis de ambiente da sessão.
- Arquivos binários grandes (PDFs) passam pelo Git LFS, conforme o `.gitattributes`.
