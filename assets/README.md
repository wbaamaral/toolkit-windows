# Assets Visuais do WBA Windows Toolkit

Este diretório armazena imagens, logos e ícones usados nos relatórios HTML e na documentação do projeto.

## Estrutura

```
assets/
├── images/
│   ├── logo.svg         # Logo principal (vetorial, preferencial)
│   ├── logo-32.png      # Favicon / ícone pequeno
│   └── logo-128.png     # Logo médio para relatórios
└── README.md            # Este arquivo
```

## Como Usar

### Logo Automático

O motor HTML detecta automaticamente `assets/images/logo.svg` e o embute como base64 nos relatórios. Não é necessário configurar nada.

Para desabilitar o logo em um relatório específico, passe `$LogoPath = $null` ou aponte para um diretório vazio.

### Logo Personalizado

Use a função `Get-ReportLogoBase64` do módulo `WbaToolkit.Core`:

```powershell
$logoUri = Get-ReportLogoBase64 -Size 'header'
# Retorna: "data:image/svg+xml;base64,..." ou $null se não encontrar
```

### Especificações

| Propriedade | Padrão |
|---|---|
| Formato preferencial | SVG (vetorial, escalável) |
| Formatos aceitos | SVG, PNG, JPG |
| Tamanho máximo (header) | 200×60px |
| Tamanho máximo (footer) | 120×40px |
| Tamanho máximo (ícone) | 32×32px |
| Peso máximo | 50KB (SVG), 20KB (PNG) |
| Fundo | Transparente ou compatível com header gradiente |

### Cores Recomendadas

Usar a paleta do projeto para consistência visual:

- Primária: `#1e3a5f` (navy escuro)
- Acento: `#2563eb` (azul brilhante)
- Sucesso: `#16a34a` (verde)
- Aviso: `#d97706` (amarelo/laranja)
- Perigo: `#dc2626` (vermelho)

## Notas

- Imagens são embutidas como base64 para manter HTML standalone (sem dependências externas)
- SVGs são rastreados pelo git (configurado no `.gitignore`)
- PNGs também são rastreados — não há regras que os excluam
- Para edição de logos, usar ferramentas vetoriais (Inkscape, Figma, Illustrator)
