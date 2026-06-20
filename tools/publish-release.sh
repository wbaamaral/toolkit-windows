#!/usr/bin/env bash
# Publica releases sincronizadas no Codeberg (codebase) e no Gitea local (especificações).
#
# Uso:
#   bash tools/publish-release.sh [--code-version v1.3.0] [--spec-version v1.2.0] [--dry-run]
#
# Variáveis de ambiente obrigatórias:
#   CODEBERG_TOKEN   — token Codeberg com escopo write:release
#   GITEA_TOKEN      — token Gitea local com escopo write:release
#
# Variáveis de ambiente opcionais:
#   GITEA_BASE_URL   — base URL do Gitea (padrão: http://192.168.5.235:3000)
#   CODE_DIR         — diretório local do codebase (padrão: detectado via git)
#   SPEC_DIR         — diretório local do spec (padrão: detectado via git)

set -euo pipefail

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
CODEBERG_OWNER="wbaamaral"
CODEBERG_REPO="wba-windows-toolkit"
CODEBERG_API="https://codeberg.org/api/v1"

GITEA_OWNER="wbaamaral"
GITEA_REPO="spec-win-toolkit"
GITEA_BASE_URL="${GITEA_BASE_URL:-http://192.168.5.235:3000}"
GITEA_API="${GITEA_BASE_URL}/api/v1"

DEFAULT_CODE_VERSION="v1.3.0"
DEFAULT_SPEC_VERSION="v1.2.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CODE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_SPEC_DIR="/home/wbaamaral/Desenvolvimento/win/spec-win-toolkit"

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
CODE_VERSION="${DEFAULT_CODE_VERSION}"
SPEC_VERSION="${DEFAULT_SPEC_VERSION}"
CODE_DIR="${CODE_DIR:-${DEFAULT_CODE_DIR}}"
SPEC_DIR="${SPEC_DIR:-${DEFAULT_SPEC_DIR}}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --code-version) CODE_VERSION="$2"; shift 2 ;;
        --spec-version) SPEC_VERSION="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=true; shift ;;
        *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
info() { echo "  → $*"; }
warn() { echo "  ! $*" >&2; }

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------
validate_env() {
    local missing=()
    [[ -z "${CODEBERG_TOKEN:-}" ]] && missing+=("CODEBERG_TOKEN")
    [[ -z "${GITEA_TOKEN:-}" ]]    && missing+=("GITEA_TOKEN")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Erro crítico: variáveis de ambiente não definidas: ${missing[*]}" >&2
        echo "" >&2
        echo "Exportar antes de executar:" >&2
        for v in "${missing[@]}"; do
            echo "  export ${v}=<seu-token>" >&2
        done
        echo "" >&2
        echo "Gerar tokens em:" >&2
        echo "  Codeberg → Settings → Applications → Generate Token (escopo: write:release)" >&2
        echo "  Gitea    → Settings → Applications → Manage Access Tokens (escopo: write:release)" >&2
        exit 1
    fi

    for dep in git curl python3; do
        if ! command -v "$dep" &>/dev/null; then
            echo "Erro: dependência ausente: ${dep}" >&2
            exit 1
        fi
    done
}

validate_dirs() {
    if [[ ! -d "${CODE_DIR}/.git" ]]; then
        echo "Erro: CODE_DIR não é um repositório git: ${CODE_DIR}" >&2; exit 1
    fi
    if [[ ! -d "${SPEC_DIR}/.git" ]]; then
        echo "Erro: SPEC_DIR não é um repositório git: ${SPEC_DIR}" >&2; exit 1
    fi
    if [[ ! -f "${CODE_DIR}/RELEASE-NOTES.md" ]]; then
        echo "Erro: RELEASE-NOTES.md não encontrado em ${CODE_DIR}" >&2; exit 1
    fi
}

check_existing_tags() {
    local code_tag spec_tag

    code_tag=$(git -C "${CODE_DIR}" tag --list "${CODE_VERSION}" 2>/dev/null)
    spec_tag=$(git -C "${SPEC_DIR}" tag --list "${SPEC_VERSION}" 2>/dev/null)

    if [[ -n "$code_tag" ]]; then
        echo "Erro: tag ${CODE_VERSION} já existe no codebase." >&2
        echo "  Use --code-version para especificar outra versão ou remova a tag localmente." >&2
        exit 1
    fi
    if [[ -n "$spec_tag" ]]; then
        echo "Erro: tag ${SPEC_VERSION} já existe no spec." >&2
        echo "  Use --spec-version para especificar outra versão ou remova a tag localmente." >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Corpo da release do Gitea (spec-win-toolkit)
# ---------------------------------------------------------------------------
spec_release_body() {
    local version="$1"
    local commit_hash
    commit_hash=$(git -C "${SPEC_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local release_date
    release_date=$(date '+%Y-%m-%d')

    cat <<SPECEOF
# WBA Windows Toolkit — Especificações ${version}

> **${version}** · Repositório de governança e especificações formais do wba-windows-toolkit

---

## Escopo desta release

Sincronização das especificações com o ciclo de desenvolvimento pós-v1.1.4, cobrindo
validação operacional em PS 5.1/7.6.2, code review DEV-019/DEV-020, backlog atualizado
e rastreamento de novos itens de robustez de testes.

---

## Alterações estruturais

| Área | Tipo | Descrição |
|---|---|---|
| \`spec/BACKLOG.md\` | Adicionado | BCK-008 a BCK-017: achados do code review e validação operacional |
| \`spec/IMPLEMENTADO.md\` | Atualizado | DEV-019, DEV-020, DEV-021 registrados; validação PS 5.1/7.6.2 |
| \`spec/estado/manifesto-estado.yml\` | Atualizado | Estado operacional sincronizado com v1.2.0/v1.3.0 |
| \`spec/STATUS.md\` | Atualizado | Resumo executivo e estado funcional alinhados |
| \`spec/BLOQUEIOS.md\` | Atualizado | BCK-001 (validação AD) registrado como bloqueio ativo |

## Itens de backlog registrados

| ID | Módulo | Descrição resumida |
|---|---|---|
| BCK-008 | Maintenance | Parsing DISM dependente de idioma (PT-BR) |
| BCK-009 | Maintenance | Robustez do hive do perfil Default (unload/retry) |
| BCK-010 | Networking | Correções no módulo de conectividade |
| BCK-011 | Maintenance | Endurecer operações de alto risco |
| BCK-012 | geral/release | Sincronizar versões dos módulos e RELEASE-NOTES |
| BCK-013 | ferramentas | Correções nas ferramentas Python do quadro operacional |
| BCK-014 | geral | Padrão de feedback/UX ao operador |
| BCK-015 | Maintenance | Achados da validação operacional do limpeza-windows |
| BCK-016 | testes | Mockar DISM/chkdsk nos testes do Maintenance |
| BCK-017 | testes | Teste de documentação dependente do CWD |

> **Breaking changes:** nenhum. Esta release é exclusivamente de documentação e especificação.

---

_${release_date} · \`${commit_hash}\` · Especificações do wba-windows-toolkit_
SPECEOF
}

# ---------------------------------------------------------------------------
# Operações git
# ---------------------------------------------------------------------------
create_code_tag() {
    log "Criando tag anotada ${CODE_VERSION} no codebase..."

    local commit_hash
    commit_hash=$(git -C "${CODE_DIR}" rev-parse --short HEAD)
    local tag_msg="Release ${CODE_VERSION} — validação operacional, hardening e laboratório AD (${commit_hash})"

    run git -C "${CODE_DIR}" config user.name  "wbaamaral"
    run git -C "${CODE_DIR}" config user.email "wbaamaral@gmail.com"
    run git -C "${CODE_DIR}" tag -a "${CODE_VERSION}" -m "${tag_msg}"
    info "Tag ${CODE_VERSION} criada em ${commit_hash}"
}

create_spec_tag() {
    log "Criando tag anotada ${SPEC_VERSION} no spec..."

    local commit_hash
    commit_hash=$(git -C "${SPEC_DIR}" rev-parse --short HEAD)
    local tag_msg="Release ${SPEC_VERSION} — sincronização pós-validação operacional PS 5.1/7.6.2 (${commit_hash})"

    run git -C "${SPEC_DIR}" config user.name  "wbaamaral"
    run git -C "${SPEC_DIR}" config user.email "wbaamaral@gmail.com"
    run git -C "${SPEC_DIR}" tag -a "${SPEC_VERSION}" -m "${tag_msg}"
    info "Tag ${SPEC_VERSION} criada em ${commit_hash}"
}

push_code_tags() {
    log "Enviando commits e tags do codebase para Codeberg..."
    run git -C "${CODE_DIR}" push origin main
    run git -C "${CODE_DIR}" push origin "${CODE_VERSION}"
    info "Codebase sincronizado."
}

push_spec_tags() {
    log "Enviando commits e tags do spec para Gitea..."
    run git -C "${SPEC_DIR}" push origin main
    run git -C "${SPEC_DIR}" push origin "${SPEC_VERSION}"
    info "Spec sincronizado."
}

# ---------------------------------------------------------------------------
# API — Codeberg
# ---------------------------------------------------------------------------
create_codeberg_release() {
    log "Criando release ${CODE_VERSION} no Codeberg..."

    local notes_file="${CODE_DIR}/RELEASE-NOTES.md"
    local payload

    payload=$(python3 - "${CODE_VERSION}" "WBA Windows Toolkit ${CODE_VERSION}" "${notes_file}" <<'PYEOF'
import sys, json
tag, title, notes_file = sys.argv[1], sys.argv[2], sys.argv[3]
body = open(notes_file, encoding='utf-8').read()
print(json.dumps({
    "tag_name":         tag,
    "target_commitish": "main",
    "name":             title,
    "body":             body,
    "draft":            False,
    "prerelease":       False
}))
PYEOF
)

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [dry-run] POST ${CODEBERG_API}/repos/${CODEBERG_OWNER}/${CODEBERG_REPO}/releases"
        echo "  [dry-run] payload truncado: $(echo "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tag_name'], '|', d['name'][:60])")"
        return
    fi

    local response http_code body_resp
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "${CODEBERG_API}/repos/${CODEBERG_OWNER}/${CODEBERG_REPO}/releases" \
        -H "Authorization: token ${CODEBERG_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    http_code=$(echo "$response" | tail -n1)
    body_resp=$(echo "$response" | head -n-1)

    if [[ "$http_code" == "201" ]]; then
        local url
        url=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('html_url',''))" <<< "$body_resp" 2>/dev/null || echo "")
        info "Release Codeberg criada."
        [[ -n "$url" ]] && info "URL: ${url}"
    else
        echo "Erro HTTP ${http_code} ao criar release no Codeberg:" >&2
        echo "$body_resp" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# API — Gitea
# ---------------------------------------------------------------------------
create_gitea_release() {
    log "Criando release ${SPEC_VERSION} no Gitea (${GITEA_BASE_URL})..."

    local tmp_body
    tmp_body=$(mktemp /tmp/wba-spec-release-XXXXXX.md)

    spec_release_body "${SPEC_VERSION}" > "${tmp_body}"

    local payload
    payload=$(python3 - "${SPEC_VERSION}" "WBA Windows Toolkit — Especificações ${SPEC_VERSION}" "${tmp_body}" <<'PYEOF'
import sys, json
tag, title, body_file = sys.argv[1], sys.argv[2], sys.argv[3]
body = open(body_file, encoding='utf-8').read()
print(json.dumps({
    "tag_name":         tag,
    "target_commitish": "main",
    "name":             title,
    "body":             body,
    "draft":            False,
    "prerelease":       False
}))
PYEOF
)

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [dry-run] POST ${GITEA_API}/repos/${GITEA_OWNER}/${GITEA_REPO}/releases"
        echo "  [dry-run] payload truncado: $(echo "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tag_name'], '|', d['name'][:60])")"
        rm -f "${tmp_body}"
        return
    fi

    local response http_code body_resp
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "${GITEA_API}/repos/${GITEA_OWNER}/${GITEA_REPO}/releases" \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    http_code=$(echo "$response" | tail -n1)
    body_resp=$(echo "$response" | head -n-1)

    rm -f "${tmp_body}"

    if [[ "$http_code" == "201" ]]; then
        local url
        url=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('html_url',''))" <<< "$body_resp" 2>/dev/null || echo "")
        info "Release Gitea criada."
        [[ -n "$url" ]] && info "URL: ${url}"
    else
        echo "Erro HTTP ${http_code} ao criar release no Gitea:" >&2
        echo "$body_resp" >&2
        exit 1
    fi
}

update_codeberg_description() {
    log "Atualizando descrição do repositório no Codeberg..."

    local new_desc="Toolkit PowerShell 5.1 para administração Windows. v1.3.0: 60 funções, 17 scripts, validação operacional PS 5.1/7.6.2."
    local payload
    payload=$(python3 -c "import json, sys; print(json.dumps({'description': sys.argv[1]}))" "$new_desc")

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [dry-run] PATCH ${CODEBERG_API}/repos/${CODEBERG_OWNER}/${CODEBERG_REPO}"
        echo "  [dry-run] description: ${new_desc}"
        return
    fi

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PATCH "${CODEBERG_API}/repos/${CODEBERG_OWNER}/${CODEBERG_REPO}" \
        -H "Authorization: token ${CODEBERG_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [[ "$http_code" == "200" ]]; then
        info "Descrição do Codeberg atualizada."
    else
        warn "Não foi possível atualizar a descrição (HTTP ${http_code}). Verificar permissão write:repository no token."
    fi
}

# ---------------------------------------------------------------------------
# Sumário pré-execução
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────"
    echo "│  WBA Windows Toolkit — Release Sincronizada"
    echo "├─────────────────────────────────────────────────────────"
    printf "│  %-24s %s\n" "Codebase (Codeberg):"  "${CODE_VERSION}"
    printf "│  %-24s %s\n" "Spec (Gitea local):"   "${SPEC_VERSION}"
    printf "│  %-24s %s\n" "Gitea endpoint:"        "${GITEA_BASE_URL}"
    printf "│  %-24s %s\n" "Code dir:"              "${CODE_DIR}"
    printf "│  %-24s %s\n" "Spec dir:"              "${SPEC_DIR}"
    [[ "$DRY_RUN" == true ]] && printf "│  %-24s %s\n" "Modo:" "DRY-RUN (nenhuma alteração será feita)"
    echo "└─────────────────────────────────────────────────────────"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    validate_env
    validate_dirs
    check_existing_tags
    print_summary

    if [[ "$DRY_RUN" == false ]]; then
        read -rp "Confirmar publicação? [s/N] " confirm
        [[ "${confirm,,}" != "s" ]] && { echo "Cancelado."; exit 0; }
        echo ""
    fi

    log "Iniciando processo de release..."
    echo ""

    create_code_tag
    create_spec_tag
    echo ""

    push_code_tags
    push_spec_tags
    echo ""

    create_codeberg_release
    create_gitea_release
    update_codeberg_description
    echo ""

    log "Processo concluído."
    echo ""
    echo "  Codebase: https://codeberg.org/${CODEBERG_OWNER}/${CODEBERG_REPO}/releases/tag/${CODE_VERSION}"
    echo "  Spec:     ${GITEA_BASE_URL}/${GITEA_OWNER}/${GITEA_REPO}/releases/tag/${SPEC_VERSION}"
    echo ""
}

main "$@"
