#!/usr/bin/env bash
# Compila o CSS dos relatorios/portal HTML via Tailwind CLI standalone e o
# embute nos geradores de HTML (ADR 0012/0025, spec-win-toolkit).
#
# Uso:
#   bash tools/build-report-css.sh
#
# Dependencias:
#   Tailwind CLI standalone (binario unico, sem Node.js) em tools/bin/tailwindcss
#
# Instalacao (Linux x64; troque o asset para outra plataforma se necessario):
#   mkdir -p tools/bin
#   curl -fsSL -o tools/bin/tailwindcss \
#     https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64
#   chmod +x tools/bin/tailwindcss

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

TAILWIND_BIN="tools/bin/tailwindcss"
TAILWIND_DIR="tools/tailwind"
OUTPUT_CSS="build/report.css"
TARGET_FILES=(
    "modules/WbaToolkit.Networking/Private/ConvertTo-ConnectivityReportHtml.ps1"
    "modules/WbaToolkit.Core/Private/ConvertTo-StaticDocsHtml.ps1"
    "scripts/inventario-hardware-software.ps1"
    "scripts/analisar-espaco-disco.ps1"
)

# ── Verificar dependência ────────────────────────────────────────────────────
if [[ ! -x "$TAILWIND_BIN" ]]; then
    echo "Erro: '$TAILWIND_BIN' não encontrado ou não executável. Consulte os comentários deste script para instalação." >&2
    exit 1
fi

# ── Passo 0: Gerar @font-face com fontes embutidas ──────────────────────────
echo "Passo 0/4: Gerando @font-face com fontes embutidas ..."
if [[ -x "tools/embed-fonts.sh" ]]; then
    bash tools/embed-fonts.sh
    # Injetar fonts.css no input.css via marcador FONT-CSS
    FONTS_CSS="$TAILWIND_DIR/build/fonts.css"
    INPUT_CSS="$TAILWIND_DIR/input.css"
    if [[ -f "$FONTS_CSS" ]]; then
        python3 - "$FONTS_CSS" "$INPUT_CSS" <<'PYEOF'
import sys

fonts_path, input_path = sys.argv[1], sys.argv[2]
fonts_css = open(fonts_path, encoding="utf-8").read().strip()
text = open(input_path, encoding="utf-8").read()

block = (
    "/* FONT-CSS:BEGIN (gerado por tools/embed-fonts.sh — nao editar) */\n"
    f"{fonts_css}\n"
    "/* FONT-CSS:END */"
)

import re
pattern = re.compile(r"/\* FONT-CSS:BEGIN.*?/\* FONT-CSS:END \*/", re.DOTALL)
new_text, count = pattern.subn(block, text)
if count != 1:
    sys.exit(f"Erro: esperava 1 bloco FONT-CSS em {input_path}, encontrou {count}.")

open(input_path, "w", encoding="utf-8").write(new_text)
print(f"  Fontes injetadas em {input_path}")
PYEOF
    fi
else
    echo "  tools/embed-fonts.sh nao encontrado — pulando injecao de fontes."
fi

# ── Passo 1: Tailwind CLI → CSS compilado ───────────────────────────────────
echo "Passo 1/4: Tailwind CLI → $TAILWIND_DIR/$OUTPUT_CSS ..."
"./$TAILWIND_BIN" --cwd "$TAILWIND_DIR" -i input.css -o "$OUTPUT_CSS" --minify

# ── Passo 2: Guarda contra caracteres que quebrariam o here-string PowerShell ─
echo "Passo 2/4: Validando CSS compilado ..."
if grep -qE '[$`]' "$TAILWIND_DIR/$OUTPUT_CSS"; then
    echo "FALHA: CSS compilado contém \$ ou backtick — revisar manualmente antes de embutir." >&2
    exit 1
fi
echo "  OK — nenhum caractere de risco encontrado."

# ── Passo 3: Embutir nos geradores de HTML ──────────────────────────────────
echo "Passo 3/4: Embutindo CSS em ${#TARGET_FILES[@]} arquivo(s) ..."
for target in "${TARGET_FILES[@]}"; do
    python3 - "$TAILWIND_DIR/$OUTPUT_CSS" "$target" <<'PYEOF'
import re
import sys

css_path, target_path = sys.argv[1], sys.argv[2]
css = open(css_path, encoding="utf-8").read().strip()
text = open(target_path, encoding="utf-8").read()

block = (
    "    # TAILWIND-CSS:BEGIN (gerado por tools/build-report-css.sh — nao editar a mao)\n"
    "    $tailwindCss = @'\n"
    f"{css}\n"
    "'@\n"
    "    # TAILWIND-CSS:END"
)

pattern = re.compile(
    r"    # TAILWIND-CSS:BEGIN.*?# TAILWIND-CSS:END",
    re.DOTALL,
)
new_text, count = pattern.subn(block, text)
if count != 1:
    sys.exit(f"Erro: esperava 1 bloco TAILWIND-CSS em {target_path}, encontrou {count}.")

open(target_path, "w", encoding="utf-8").write(new_text)
print(f"  Embutido em {target_path}")
PYEOF
done

echo "CSS dos relatórios atualizado com sucesso."
