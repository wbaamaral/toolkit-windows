#!/usr/bin/env bash
# embed-fonts.sh — Converte fontes WOFF2 para base64 e gera @font-face CSS
#
# Uso:
#   bash tools/embed-fonts.sh
#
# Saidas:
#   tools/tailwind/build/fonts.css — Bloco @font-face com data URIs base64
#
# O CSS gerado deve ser injetado no input.css via marcador FONT-CSS:BEGIN/END

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

FONTS_DIR="assets/fonts"
BUILD_DIR="tools/tailwind/build"
OUTPUT="$BUILD_DIR/fonts.css"

mkdir -p "$BUILD_DIR"

echo "Gerando @font-face com fontes embutidas em base64..."

# Iniciar bloco CSS
cat > "$OUTPUT" <<'HEADER'
/* ---- Fontes self-hosted (gerado por tools/embed-fonts.sh — nao editar) ---- */
HEADER

# Funcao para gerar @font-face de um arquivo WOFF2
generate_font_face() {
    local file="$1"
    local family="$2"
    local weight="$3"
    local basename=$(basename "$file")
    local b64=$(base64 -w 0 "$file" 2>/dev/null || base64 "$file" 2>/dev/null)
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)

    cat >> "$OUTPUT" <<EOF
@font-face {
  font-family: '$family';
  font-style: normal;
  font-weight: $weight;
  font-display: swap;
  src: url('data:font/woff2;base64,$b64') format('woff2');
}

EOF
    echo "  $basename ($family $weight): $(( size / 1024 ))KB → base64 OK"
}

# Inter
generate_font_face "$FONTS_DIR/Inter-Regular.woff2" "Inter" "400"
generate_font_face "$FONTS_DIR/Inter-Bold.woff2" "Inter" "700"

# JetBrains Mono
generate_font_face "$FONTS_DIR/JetBrainsMono-Regular.woff2" "JetBrains Mono" "400"
generate_font_face "$FONTS_DIR/JetBrainsMono-Bold.woff2" "JetBrains Mono" "700"

echo ""
echo "CSS gerado em: $OUTPUT ($(wc -c < "$OUTPUT" | xargs) bytes)"
echo "Fontes embutidas com sucesso."
