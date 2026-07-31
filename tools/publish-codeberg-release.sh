#!/usr/bin/env bash
# Publica uma release no Codeberg usando RELEASE-NOTES.md como corpo.
# Uso: bash tools/publish-codeberg-release.sh <tag> <titulo>
# Exemplo: bash tools/publish-codeberg-release.sh v1.1.2 "WBA Windows Toolkit v1.1.2"
#
# Requer CODEBERG_TOKEN exportado na sessão:
#   export CODEBERG_TOKEN=seu_token_aqui
# Gerar token: Codeberg → Settings → Applications → Generate Token (escopo: write:release)

set -euo pipefail

REPO_OWNER="wbaamaral"
REPO_NAME="wba-windows-toolkit"
NOTES_FILE="RELEASE-NOTES.md"

TAG="${1:-}"
TITLE="${2:-}"

if [[ -z "$TAG" || -z "$TITLE" ]]; then
    echo "Uso: bash tools/publish-codeberg-release.sh <tag> <titulo>" >&2
    echo "Exemplo: bash tools/publish-codeberg-release.sh v1.1.2 \"WBA Windows Toolkit v1.1.2\"" >&2
    exit 1
fi

if [[ -z "${CODEBERG_TOKEN:-}" ]]; then
    echo "Erro: CODEBERG_TOKEN não definido." >&2
    echo "Exportar antes de executar: export CODEBERG_TOKEN=seu_token_aqui" >&2
    echo "Gerar em: Codeberg → Settings → Applications → Generate Token (escopo: write:release)" >&2
    exit 1
fi

if [[ ! -f "$NOTES_FILE" ]]; then
    echo "Erro: $NOTES_FILE não encontrado. Executar a partir da raiz do repositório." >&2
    exit 1
fi

# Montar payload JSON de forma segura via Python (evita injeção por caracteres especiais)
PAYLOAD=$(python3 - "$TAG" "$TITLE" "$NOTES_FILE" <<'PYEOF'
import sys, json
tag, title, notes_file = sys.argv[1], sys.argv[2], sys.argv[3]
body = open(notes_file, encoding='utf-8').read()
print(json.dumps({
    "tag_name":   tag,
    "name":       title,
    "body":       body,
    "draft":      False,
    "prerelease": False
}))
PYEOF
)

echo "Publicando release $TAG no Codeberg..."

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "https://codeberg.org/api/v1/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
    -H "Authorization: token ${CODEBERG_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY_RESP=$(echo "$RESPONSE" | head -n-1)

if [[ "$HTTP_CODE" == "201" ]]; then
    RELEASE_URL=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('html_url',''))" <<< "$BODY_RESP" 2>/dev/null || echo "")
    echo "Release publicada com sucesso."
    [[ -n "$RELEASE_URL" ]] && echo "URL: $RELEASE_URL"
else
    echo "Erro HTTP $HTTP_CODE ao publicar release:" >&2
    echo "$BODY_RESP" >&2
    exit 1
fi
