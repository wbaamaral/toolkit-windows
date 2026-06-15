#!/usr/bin/env bash
# Gera o PDF do manual do operador via Pandoc + LuaLaTeX.
# Uso: bash tools/build-pdf.sh
# Requer: pandoc >= 3.x e lualatex (TeX Live)

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SOURCE="docs/manual-operador-wba-windows-toolkit.md"
OUTPUT="docs/manual-operador-wba-windows-toolkit.pdf"
DEFAULTS="docs/latex/pandoc-defaults.yaml"

if ! command -v pandoc &>/dev/null; then
    echo "Erro: pandoc não encontrado. Instale com: pacman -S pandoc" >&2; exit 1
fi
if ! command -v lualatex &>/dev/null; then
    echo "Erro: lualatex não encontrado. Instale com: pacman -S texlive-bin" >&2; exit 1
fi

echo "Gerando $OUTPUT ..."
pandoc "$SOURCE" --defaults="$DEFAULTS" -o "$OUTPUT"
echo "Concluído: $OUTPUT"
