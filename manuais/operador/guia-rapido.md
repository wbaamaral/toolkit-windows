# Guia Rápido do Operador - WBA Windows Toolkit

Autor: **wbaamaral** — v1.2.0

Manual completo: [`../manual-operador-wba-windows-toolkit.md`](../manual-operador-wba-windows-toolkit.md)
Portal do operador: [`README.md`](README.md)

Entrada recomendada do MVP:

```powershell
.\xtudo.ps1
```

Atalhos principais:

1. Limpar Windows
2. Diagnosticar disco 100%
3. Diagnosticar memória
4. Diagnosticar gráfico
5. Preparar imagem

---

## Pré-requisitos

```powershell
# 1. Abrir PowerShell como Administrador
# 2. Navegar até a raiz do toolkit
cd C:\ti\wba-windows-toolkit

# 3. Liberar execução de scripts (somente esta sessão)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 4. Importar módulo principal (quando necessário)
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
```

---

## Scripts do MVP

### Diagnóstico de rede

```powershell
.\scripts\testar-conectividade-internet.ps1
.\scripts\testar-conectividade-internet.ps1 -Detalhado
```

### Diagnóstico de disco (HD100)

```powershell
.\scripts\diagnosticar-disco-100.ps1
.\scripts\diagnosticar-disco-100.ps1 -GerarHtml
.\scripts\diagnosticar-disco-100.ps1 -Modo Assistido -GerarHtml
.\scripts\diagnosticar-disco-100.ps1 -DryRun
```

### Diagnóstico de driver gráfico

```powershell
.\scripts\diagnosticar-grafico.ps1
.\scripts\diagnosticar-grafico.ps1 -GerarHtml
.\scripts\diagnosticar-grafico.ps1 -GerarHtml -ColetarDxDiag -ExportarEvtx
```

### Diagnóstico de memória

```powershell
.\scripts\diagnosticar-memoria.ps1
.\scripts\diagnosticar-memoria.ps1 -Top 20
.\scripts\diagnosticar-memoria.ps1 -Todos
.\scripts\diagnosticar-memoria.ps1 -GerarHtml
```

### Verificar atualizações de hardware

```powershell
.\scripts\verificar-atualizacoes-hardware.ps1
.\scripts\verificar-atualizacoes-hardware.ps1 -GerarHtml
.\scripts\verificar-atualizacoes-hardware.ps1 -SkipDrivers
.\scripts\verificar-atualizacoes-hardware.ps1 -SkipBios
```

### Limpeza do Windows

```powershell
.\scripts\limpar-windows.ps1 -NoReboot
.\scripts\limpar-windows.ps1 -RepararSistema -NoReboot
.\scripts\limpar-windows.ps1 -NoSfc -NoReboot
.\scripts\limpar-windows.ps1 -DisableHibernation -NoReboot
```

### Limpeza do WinSxS

```powershell
.\scripts\limpar-winsxs.ps1
.\scripts\limpar-winsxs.ps1 -Modo Relatorio
.\scripts\limpar-winsxs.ps1 -Modo Relatorio -GerarHtml
.\scripts\limpar-winsxs.ps1 -Modo Limpeza
.\scripts\limpar-winsxs.ps1 -Modo Limpeza -DryRun
```

### Preparar imagem corporativa

```powershell
.\scripts\preparar-imagem-windows.ps1 -ApenasDryRun
.\scripts\preparar-imagem-windows.ps1 -SemSysprep
.\scripts\preparar-imagem-windows.ps1
```

### Atualizar Windows

```powershell
.\scripts\atualizar-windows.ps1
.\scripts\atualizar-windows.ps1 -Backend WinGet
.\scripts\atualizar-windows.ps1 -Backend WinGet -Action ListOnly
.\scripts\atualizar-windows.ps1 -Backend Chocolatey -NoWindowsUpdate
.\scripts\atualizar-windows.ps1 -NoWindowsUpdate
```

---

## Navegação

- Catálogo de manuais: [`../README.md`](../README.md)
- Manual completo do operador: [`../manual-operador-wba-windows-toolkit.md`](../manual-operador-wba-windows-toolkit.md)
