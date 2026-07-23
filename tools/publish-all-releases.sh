#!/usr/bin/env bash
# Publica todas as releases históricas no Codeberg.
# Requer CODEBERG_TOKEN exportado e "Releases" habilitado no repositório.
# Executar da raiz do repositório.

set -euo pipefail

REPO_OWNER="wbaamaral"
REPO_NAME="wba-windows-toolkit"
TOKEN="${CODEBERG_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
    echo "Erro: CODEBERG_TOKEN não definido." >&2; exit 1
fi

post_release() {
    local tag="$1" title="$2" body="$3"
    local payload
    payload=$(python3 -c "
import sys, json
print(json.dumps({
    'tag_name':   sys.argv[1],
    'name':       sys.argv[2],
    'body':       sys.argv[3],
    'draft':      False,
    'prerelease': False
}))" "$tag" "$title" "$body")

    local response http_code
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://codeberg.org/api/v1/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
        -H "Authorization: token ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    http_code=$(echo "$response" | tail -1)
    local resp_body
    resp_body=$(echo "$response" | head -n-1)

    if [[ "$http_code" == "201" ]]; then
        local url
        url=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('html_url',''))" <<< "$resp_body" 2>/dev/null || echo "")
        echo "  ✔ $tag publicada — $url"
    elif [[ "$http_code" == "422" ]]; then
        echo "  ⚠ $tag já possui release — ignorada"
    else
        echo "  ✘ $tag erro $http_code: $resp_body" >&2
    fi
}

echo "=== Publicando releases no Codeberg ==="

# ── v0.1.0 ──────────────────────────────────────────────────────────────────
post_release "v0.1.0" "WBA Windows Toolkit v0.1.0" \
"# WBA Windows Toolkit — v0.1.0

> **v0.1.0** · PowerShell 5.1 · Windows 10 / Server 2016+

Release inicial do toolkit.

## Adicionado

- Módulo \`WbaToolkit.Core\` com funções utilitárias compartilhadas
- Módulo \`WbaToolkit.Networking\` com testes de conectividade TCP/UDP/ICMP/DNS
- Script \`Diagnostico-Reparo-HD100.ps1\` com diagnóstico de disco e relatório HTML"

# ── v1.0.0 ──────────────────────────────────────────────────────────────────
post_release "v1.0.0" "WBA Windows Toolkit v1.0.0" \
"# WBA Windows Toolkit — v1.0.0

> **v1.0.0** · PowerShell 5.1 · Windows 10 / Server 2016+

Consolidação da arquitetura modular. Dois novos módulos, novos scripts e padronização completa.

## 📦 Módulos (v1.0.0)

| Módulo | Funções |
|---|---|
| \`WbaToolkit.Core\` | 23 |
| \`WbaToolkit.Networking\` | 16 |
| \`WbaToolkit.Startup\` | 7 |
| \`WbaToolkit.Maintenance\` | 5 |

## Adicionado

- Módulo \`WbaToolkit.Startup\`: lista, habilita, desabilita e remove itens de inicialização do Windows
- Módulo \`WbaToolkit.Maintenance\`: prepara imagem corporativa para sysprep com dry-run e backup automático
- Script \`Gerenciar-Inicializacao-Windows.ps1\`: interface assistida para startup
- Script \`Preparar-Imagem-Windows.ps1\`: tweaks de perfil Default + sysprep
- Funções \`WbaToolkit.Core\`: Read-UserInput, Write-ScriptLog, Initialize-ScriptSession, Get-CimInstanceSafe, Write-TextFileUtf8, Get-Utf8BomEncoding, Get-ToolkitConfiguration
- Exportação de resumo de drivers de hardware em inventário
- Assistente de conectividade com suporte a múltiplos protocolos por destino
- Diagnóstico de driver gráfico com relatório TXT

## Corrigido

- Criação da sessão de relatório padrão adiada para evitar diretórios vazios em execuções sem saída

## Alterado

- Scripts HD100, Gráficos e AD refatorados para usar funções do \`WbaToolkit.Core\`
- Sessões de saída de relatório padronizadas em todos os scripts de diagnóstico"

# ── v1.0.1 ──────────────────────────────────────────────────────────────────
post_release "v1.0.1" "WBA Windows Toolkit v1.0.1" \
"# WBA Windows Toolkit — v1.0.1

> **v1.0.1** · PowerShell 5.1 · Windows 10 / Server 2016+

Versão de manutenção da documentação.

## Adicionado

- Estrutura \`docs/manual/\` com catálogo geral de scripts por função operacional, guia rápido do operador e referência de módulos e funções públicas"

# ── v1.1.0 ──────────────────────────────────────────────────────────────────
post_release "v1.1.0" "WBA Windows Toolkit v1.1.0" \
"# WBA Windows Toolkit — v1.1.0

> **v1.1.0** · PowerShell 5.1 · Windows 10 / Server 2016+

Nova função pública \`Export-ToolkitDocumentation\`: portal HTML offline completo gerado a partir dos módulos e da documentação editorial.

## 📦 Módulos (v1.1.0)

| Módulo | Funções |
|---|---|
| \`WbaToolkit.Core\` | 24 |
| \`WbaToolkit.Networking\` | 16 |
| \`WbaToolkit.Startup\` | 7 |
| \`WbaToolkit.Maintenance\` | 5 |
| **Total** | **52** |

## Adicionado

- \`Export-ToolkitDocumentation\` — portal HTML offline (ADR 0013); modos \`-Mode All|Portal|TechnicalReference\`
- \`ConvertFrom-MarkdownSimple\` (privada) — conversor Markdown→HTML em PS 5.1 puro
- \`New-PortalIndexHtml\` (privada) — gerador de portal index.html com cards de ação

## ⚡ Início rápido

\`\`\`powershell
Import-Module .\\modules\\WbaToolkit.Core\\WbaToolkit.Core.psd1 -Force
Export-ToolkitDocumentation -Mode All -Force
# Resultado em: .\\docs\\portal\\index.html
\`\`\`"

# ── v1.1.1 ──────────────────────────────────────────────────────────────────
post_release "v1.1.1" "WBA Windows Toolkit v1.1.1" \
"# WBA Windows Toolkit — v1.1.1

> **v1.1.1** · PowerShell 5.1 · Windows 10 / Server 2016+

Correções de documentação para alinhar \`docs/manual/\` à função \`Export-ToolkitDocumentation\` introduzida na v1.1.0.

## Alterado

- \`docs/manual/README.md\`: \`Export-ToolkitDocumentation\` adicionado na referência técnica; contagem de funções corrigida (23→24); exemplos atualizados
- \`docs/manual/referencia/modulos.md\`: \`Export-ToolkitDocumentation\` adicionado na tabela de utilitários
- \`docs/manual/operador/guia-rapido.md\`: seção de geração do portal HTML adicionada"

# ── v1.1.2 ──────────────────────────────────────────────────────────────────
post_release "v1.1.2" "WBA Windows Toolkit v1.1.2" \
"# WBA Windows Toolkit — v1.1.2

> **v1.1.2** · PowerShell 5.1 · Windows 10 / Server 2016+

Processo de release formalizado: \`RELEASE-NOTES.md\` como artefato obrigatório e script de publicação no Codeberg.

## Adicionado

- \`RELEASE-NOTES.md\`: documento de apresentação da release publicado como corpo da release no Codeberg
- \`tools/publish-codeberg-release.sh\`: publica release via API do Codeberg (curl + Python, payload JSON seguro)

## Especificações (spec-win-toolkit)

- \`processo-release.md\` reescrito: §2.3 dedicado ao RELEASE-NOTES.md, checklist expandido, Fase 3 dividida em Git e Codeberg
- ADR 0018 atualizado com §6 (RELEASE-NOTES.md como artefato obrigatório)
- \`templates/template-release-notes.md\` criado"

# ── v1.1.3 ──────────────────────────────────────────────────────────────────
post_release "v1.1.3" "WBA Windows Toolkit v1.1.3" \
"$(cat RELEASE-NOTES.md)"

echo "=== Concluído ==="
