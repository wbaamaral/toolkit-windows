# Padronização de Assets Visuais

Autor: **wbaamaral**

## Objetivo

Definir padrões técnicos para imagens, logos e ícones usados nos relatórios HTML gerados pelo toolkit, garantindo consistência visual, portabilidade dos arquivos HTML e compatibilidade com o motor de conversão.

## Estrutura de Diretórios

```
wba-windows-toolkit/
├── assets/
│   └── images/
│       ├── logo.svg         # Logo principal (vetorial)
│       ├── logo-32.png      # Favicon / ícone pequeno
│       └── logo-128.png     # Logo médio para relatórios
```

## Especificações Técnicas

### Logo Principal (Header)

| Propriedade | Valor |
|---|---|
| Formato preferencial | SVG (vetorial, escalável sem perda) |
| Formatos aceitos | SVG, PNG, JPG/JPEG |
| Dimensões máximas | 200×60px |
| Peso máximo | 50KB (SVG) / 20KB (PNG) |
| Fundo | Transparente ou compatível com header gradiente |
| Cores | Paleta do projeto: `#1e3a5f` (primária), `#2563eb` (acento) |

### Logo Footer

| Propriedade | Valor |
|---|---|
| Dimensões máximas | 120×40px |
| Opacidade padrão | 60% (via CSS `.report-logo-footer`) |
| Formato | Mesmo do logo principal |

### Ícones

| Propriedade | Valor |
|---|---|
| Formato preferencial | SVG ou Unicode emoji |
| Dimensões SVG | 32×32px (viewBox) |
| Não usar | PNG para ícones (perde qualidade em zoom) |

## Como Adicionar um Logo

### Passo 1 — Preparar a imagem

1. Criar o logo seguindo as especificações acima
2. Exportar com fundo transparente
3. Validar dimensões e peso

### Passo 2 — Salvar no diretório correto

```
assets/images/logo.svg      ← Logo principal
assets/images/logo-32.png   ← Favicon (opcional)
assets/images/logo-128.png  ← Logo médio (opcional)
```

### Passo 3 — O motor detecta automaticamente

A função `Get-ReportLogoBase64` do módulo `WbaToolkit.Core` procura por `assets/images/logo.svg` automaticamente. Se encontrar, converte para base64 e embute no HTML.

### Passo 4 — Personalização avançada

Para usar um logo diferente do padrão:

```powershell
# No script que gera HTML:
$logoUri = Get-ReportLogoBase64 -LogoPath 'C:\caminho\para\logo-custom.svg' -Size 'header'
```

## Embedding Base64

### Por que Base64?

Os relatórios HTML são **standalone** — devem funcionar via `file://` sem servidor web. Imagens externas (`<img src="logo.svg">`) quebrariam a portabilidade. Base64 embute a imagem diretamente no HTML.

### Fluxo

```
assets/images/logo.svg (arquivo fonte)
        ↓
[PowerShell] ReadAllBytes + ConvertTo-Base64String
        ↓
"data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0..."
        ↓
<img src="data:image/svg+xml;base64,..." class="report-logo">
        ↓
HTML standalone com imagem embutida
```

### Validação

Para verificar se uma imagem está corretamente embutida:

1. Abrir o HTML gerado no navegador
2. Pressionar F12 (DevTools)
3. Inspecionar o elemento `<img>`
4. Verificar se o `src` inicia com `data:image/`

## Classes CSS para Imagens

Definidas em `tools/tailwind/input.css` na camada `@layer components`:

| Classe | Uso | Dimensões |
|---|---|---|
| `.report-logo` | Logo no header | `height: 40px`, `width: auto` |
| `.report-logo-footer` | Logo no footer | `height: 24px`, `width: auto` |
| `.logo-placeholder` | Fallback quando não há logo | `40×40px`, fundo semi-transparente |

### Exemplo de Uso no HTML

```html
<!-- Com logo -->
<header>
  <div class="title-block">
    <img src="data:image/svg+xml;base64,..." class="report-logo" alt="WBA Toolkit">
    <h1>Titulo do Relatorio</h1>
  </div>
</header>

<!-- Sem logo (placeholder) -->
<header>
  <div class="title-block">
    <div class="logo-placeholder">WBA</div>
    <h1>Titulo do Relatorio</h1>
  </div>
</header>
```

## Limitações

| Regra | Motivo |
|---|---|
| Máximo 3 imagens por relatório | Controlar tamanho do HTML gerado |
| Peso máximo 50KB por imagem | HTML não deve exceder 500KB total |
| Não usar GIF animado | Relatórios são estáticos, impressos em PDF |
| SVGs devem ser self-contained | Sem dependências externas (`<defs>`, `<use>`) |
| PNGs com transparência | Fundo do header é gradiente |

## Cores da Paleta

Usar consistentemente em logos e ícones:

| Nome | Código | Uso |
|---|---|---|
| Primária | `#1e3a5f` | Fundo de headers, textos principais |
| Primária clara | `#2d5986` | Gradiente do header |
| Acento | `#2563eb` | Links, bordas de cards, destaques |
| Sucesso | `#16a34a` | Status positivo, barras OK |
| Aviso | `#d97706` | Status de atenção, barras warn |
| Perigo | `#dc2626` | Status de erro, barras danger |

## Referências

- `assets/README.md` — Documentação de uso rápido
- `tools/tailwind/input.css` — Classes CSS para imagens
- `modules/WbaToolkit.Core/Public/Get-ReportLogoBase64.ps1` — Função de embedding
- `spec/qualidade/padrao-portal-documentacao-html.md` — Padrão do portal HTML
