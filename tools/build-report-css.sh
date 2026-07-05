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
)

# ── Verificar dependência ────────────────────────────────────────────────────
if [[ ! -x "$TAILWIND_BIN" ]]; then
    echo "Erro: '$TAILWIND_BIN' não encontrado ou não executável. Consulte os comentários deste script para instalação." >&2
    exit 1
fi

# ── Passo 1: Tailwind CLI → CSS compilado ───────────────────────────────────
echo "Passo 1/3: Tailwind CLI → $TAILWIND_DIR/$OUTPUT_CSS ..."
"./$TAILWIND_BIN" --cwd "$TAILWIND_DIR" -i input.css -o "$OUTPUT_CSS" --minify

# ── Passo 2: Guarda contra caracteres que quebrariam o here-string PowerShell ─
echo "Passo 2/3: Validando CSS compilado ..."
if grep -qE '[$`]' "$TAILWIND_DIR/$OUTPUT_CSS"; then
    echo "FALHA: CSS compilado contém \$ ou backtick — revisar manualmente antes de embutir." >&2
    exit 1
fi
echo "  OK — nenhum caractere de risco encontrado."

# ── Passo 3: Embutir nos geradores de HTML ──────────────────────────────────
echo "Passo 3/3: Embutindo CSS em ${#TARGET_FILES[@]} arquivo(s) ..."
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
