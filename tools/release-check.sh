#!/usr/bin/env bash

set -euo pipefail

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
info() { printf '  -> %s\n' "$*"; }
fail() { printf 'Erro: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "não foi possível identificar a raiz git em ${REPO_ROOT}"
fi

if ! command -v git-lfs >/dev/null 2>&1; then
    fail "git-lfs não está disponível neste ambiente; a validação anti-LFS depende dele"
fi

log "Executando validação anti-LFS em ${REPO_ROOT}"

mapfile -t lfs_files < <(git -C "${REPO_ROOT}" lfs ls-files --name-only | sed '/^$/d' | sort -u)

if [[ ${#lfs_files[@]} -eq 0 ]]; then
    info "nenhum arquivo rastreado por Git LFS encontrado"
    exit 0
fi

for relative_path in "${lfs_files[@]}"; do
    local_path="${REPO_ROOT}/${relative_path}"

    [[ -f "${local_path}" ]] || fail "arquivo LFS ausente no working tree: ${relative_path}"

    if LC_ALL=C grep -a -q '^version https://git-lfs.github.com/spec/v1$' "${local_path}"; then
        fail "arquivo ainda é um ponteiro Git LFS: ${relative_path}"
    fi

    if [[ "${relative_path}" == *.pdf ]]; then
        if ! file -b "${local_path}" | grep -qi 'PDF document'; then
            fail "arquivo PDF inválido ou não resolvido como PDF real: ${relative_path}"
        fi
    fi
done

info "arquivos LFS resolvidos e validados: ${#lfs_files[@]}"
log "Validação anti-LFS concluída com sucesso"
