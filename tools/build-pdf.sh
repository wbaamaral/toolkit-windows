#!/usr/bin/env bash
# Gera o PDF do manual do operador via Pandoc + latexmk + LuaLaTeX.
#
# Uso:
#   bash tools/build-pdf.sh
#
# Dependências (TeX Live 2024+ ou equivalente):
#   pandoc  >= 3.x   — conversão Markdown → LaTeX
#   latexmk >= 4.x   — compilação LaTeX em múltiplas passagens
#   lualatex         — engine (pacote texlive-luatex ou texlive-bin)
#   fvextra, geometry, fancyhdr, booktabs, hyperref — pacotes LaTeX
#     (incluídos no texlive-latexextra e texlive-latex-recommended)
#
# Instalação no Arch Linux:
#   sudo pacman -S pandoc texlive-luatex texlive-latexextra texlive-fontsrecommended

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SOURCE="manuais/manual-operador-wba-windows-toolkit.md"
TEX_FILE="docs/latex/build/manual.tex"
BUILD_DIR="docs/latex/build"
OUTPUT="manuais/manual-operador-wba-windows-toolkit.pdf"
DEFAULTS="docs/latex/pandoc-defaults.yaml"

# ── Verificar dependências ──────────────────────────────────────────────────
for cmd in pandoc latexmk lualatex; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Erro: '$cmd' não encontrado. Consulte os comentários deste script para instalação." >&2
        exit 1
    fi
done

# ── Validação de acentuação (ADR 0019, §8) ─────────────────────────────────
echo "Validando acentuação em docs/latex/ ..."
ESCAPES=$(grep -R "\\\\'[{][aeiouAEIOU][}]\|\\\~[{][aoAO][}]\|\\\\c[{]c[}]" docs/latex/ 2>/dev/null || true)
if [[ -n "$ESCAPES" ]]; then
    echo "FALHA: acentuação escapada encontrada (proibida pelo padrão LaTeX):" >&2
    echo "$ESCAPES" >&2
    exit 1
fi
echo "  OK — nenhum escape proibido encontrado."

# ── Passo 1: Pandoc → .tex ─────────────────────────────────────────────────
echo "Passo 1/2: Pandoc → $TEX_FILE ..."
pandoc "$SOURCE" \
    --defaults="$DEFAULTS" \
    --standalone \
    -o "$TEX_FILE"

# ── Passo 2: latexmk → PDF ─────────────────────────────────────────────────
echo "Passo 2/2: latexmk → $BUILD_DIR/manual.pdf ..."
latexmk \
    -lualatex \
    -interaction=nonstopmode \
    -halt-on-error \
    -file-line-error \
    -output-directory="$BUILD_DIR" \
    "$TEX_FILE"

# ── Publicar artefato final ─────────────────────────────────────────────────
cp "$BUILD_DIR/manual.pdf" "$OUTPUT"
echo "PDF gerado: $OUTPUT"
