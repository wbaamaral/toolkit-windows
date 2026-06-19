# Guia Rápido do Operador — WBA Windows Toolkit

Autor: **wbaamaral** — v1.2.0

Manual completo: [`docs/manual-operador-wba-windows-toolkit.md`](../../manual-operador-wba-windows-toolkit.md)

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

## Scripts operacionais

### Diagnóstico de rede

```powershell
# Diagnóstico padrão:
.\diagnostics\networking\Testar-Conectividade-Internet.ps1

# Com detalhes adicionais no console:
.\diagnostics\networking\Testar-Conectividade-Internet.ps1 -Detalhado
```

### Diagnóstico de disco (HD100)

```powershell
# Diagnóstico padrão:
.\maintenance\Diagnostico-Reparo-HD100.ps1

# Com relatório HTML:
.\maintenance\Diagnostico-Reparo-HD100.ps1 -GerarHtml

# Modo assistido (oferece ações de reparo):
.\maintenance\Diagnostico-Reparo-HD100.ps1 -Modo Assistido -GerarHtml

# Simulação sem executar comandos externos:
.\maintenance\Diagnostico-Reparo-HD100.ps1 -DryRun
```

### Diagnóstico de driver gráfico

```powershell
# Diagnóstico padrão:
.\diagnostics\Diagnostico-Driver-Grafico.ps1

# Com relatório HTML:
.\diagnostics\Diagnostico-Driver-Grafico.ps1 -GerarHtml

# Coleta completa (HTML + DXDiag + exportação de log de eventos):
.\diagnostics\Diagnostico-Driver-Grafico.ps1 -GerarHtml -ColetarDxDiag -ExportarEvtx
```

### Diagnóstico de memória

```powershell
# Top 10 consumidores de RAM (padrão):
.\diagnostics\Diagnostico-Memoria.ps1

# Top 20 processos:
.\diagnostics\Diagnostico-Memoria.ps1 -Top 20

# Listar todos os processos:
.\diagnostics\Diagnostico-Memoria.ps1 -Todos

# Com relatório HTML:
.\diagnostics\Diagnostico-Memoria.ps1 -GerarHtml
```

### Verificar atualizações de hardware

```powershell
# Diagnóstico completo (BIOS + drivers + Windows Update):
.\diagnostics\Verificar-Atualizacoes-Hardware.ps1

# Com relatório HTML:
.\diagnostics\Verificar-Atualizacoes-Hardware.ps1 -GerarHtml

# Somente BIOS:
.\diagnostics\Verificar-Atualizacoes-Hardware.ps1 -SkipDrivers

# Somente drivers:
.\diagnostics\Verificar-Atualizacoes-Hardware.ps1 -SkipBios
```

### Inventário de hardware/software

```powershell
# Inventário completo (HTML + PDF quando Chrome ou Edge disponível):
.\inventory\Inventario-Hardware-Software.ps1

# Sem PDF (somente HTML):
.\inventory\Inventario-Hardware-Software.ps1 -NaoPDF

# Somente resumo de hardware e drivers:
.\inventory\Inventario-Hardware-Software.ps1 -SomenteHardwareDrivers

# Inventário completo + resumo de hardware/drivers:
.\inventory\Inventario-Hardware-Software.ps1 -GerarResumoHardwareDrivers
```

### Gerenciar inicialização

```powershell
# Somente visualização (padrão):
.\maintenance\Gerenciar-Inicializacao-Windows.ps1

# Com relatório HTML:
.\maintenance\Gerenciar-Inicializacao-Windows.ps1 -GerarHtml

# Modo assistido (permite desabilitar/habilitar entradas):
.\maintenance\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido

# Simulação sem alterar o sistema:
.\maintenance\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido -DryRun
```

### Limpeza do Windows

```powershell
# Limpeza conservadora sem reiniciar (recomendado):
.\maintenance\limpeza-windows.ps1 -NoReboot

# Somente reparar sistema (SFC + DISM):
.\maintenance\limpeza-windows.ps1 -RepararSistema -NoReboot

# Limpeza sem SFC/DISM:
.\maintenance\limpeza-windows.ps1 -NoSfc -NoReboot

# Liberar espaço do hiberfil.sys (desativa hibernação):
.\maintenance\limpeza-windows.ps1 -DisableHibernation -NoReboot
```

### Limpeza do WinSxS (Component Store)

```powershell
# Diagnóstico somente leitura (padrão):
.\maintenance\Limpeza-WinSxS.ps1

# Relatório em JSON:
.\maintenance\Limpeza-WinSxS.ps1 -Modo Relatorio

# Relatório em JSON e HTML:
.\maintenance\Limpeza-WinSxS.ps1 -Modo Relatorio -GerarHtml

# Limpeza assistida (solicita confirmação):
.\maintenance\Limpeza-WinSxS.ps1 -Modo Limpeza

# Simulação da limpeza sem alterar nada:
.\maintenance\Limpeza-WinSxS.ps1 -Modo Limpeza -DryRun
```

### Backup e restauração de drivers

```powershell
# Backup interativo (padrão):
.\maintenance\Backup-Restaurar-Drivers.ps1

# Simulação de backup:
.\maintenance\Backup-Restaurar-Drivers.ps1 -DryRun

# Restauração interativa com relatório HTML:
.\maintenance\Backup-Restaurar-Drivers.ps1 -Modo Restore -GerarHtml

# Path de relatório/backup customizado:
.\maintenance\Backup-Restaurar-Drivers.ps1 -Path "D:\Backup\Drivers"
```

### Preparar imagem corporativa (sysprep)

```powershell
# Simulação obrigatória antes de qualquer execução:
.\maintenance\Preparar-Imagem-Windows.ps1 -ApenasDryRun

# Aplicar tweaks sem iniciar sysprep:
.\maintenance\Preparar-Imagem-Windows.ps1 -SemSysprep

# Execução completa (tweaks de perfil Default + sysprep):
.\maintenance\Preparar-Imagem-Windows.ps1
```

### Configurar idioma e região

```powershell
# Configuração padrão (pt-BR, UTC-4):
.\configuration\Configurar-Idioma-Regional.ps1

# Modo silencioso sem reboot (automação, GPO, SCCM):
.\configuration\Configurar-Idioma-Regional.ps1 -Silent -NoReboot

# Fuso de Brasília (UTC-3):
.\configuration\Configurar-Idioma-Regional.ps1 -TimeZone "E. South America Standard Time"

# Listar fusos disponíveis do Brasil:
.\configuration\Configurar-Idioma-Regional.ps1 -ListTimeZones
```

### Análise de espaço em disco

```powershell
# Varrer todos os volumes locais:
.\utilities\Analise-Espaco-Disco.ps1

# Varrer somente C::
.\utilities\Analise-Espaco-Disco.ps1 -Drive C

# Sem conversão para PDF:
.\utilities\Analise-Espaco-Disco.ps1 -NaoPDF
```

### Remover perfis inativos

```powershell
# Simulação — lista o que seria removido sem alterar nada:
.\utilities\Remover-Perfis-Inativos.ps1 -DryRun

# Modo interativo (padrão):
.\utilities\Remover-Perfis-Inativos.ps1

# Automático (remove órfãos e inativos sem confirmação):
.\utilities\Remover-Perfis-Inativos.ps1 -Silent
```

### Atualizar Windows

```powershell
# Atualização completa (Windows Update + Chocolatey):
.\updates\upgrade-windows.ps1 -PauseAtEnd

# Somente Windows Update:
.\updates\upgrade-windows.ps1 -NoChocolatey -PauseAtEnd

# Somente Chocolatey:
.\updates\upgrade-windows.ps1 -NoWindowsUpdate -PauseAtEnd
```

### Diagnóstico de GPO

```powershell
# Detecção automática de domínio e DC:
.\active-directory\Diagnostico-GPO-Client.ps1

# Somente leitura com DC específico:
.\active-directory\Diagnostico-GPO-Client.ps1 -DCName DC01 -SkipReparo

# Com FQDN do domínio informado:
.\active-directory\Diagnostico-GPO-Client.ps1 -DomainFQDN contoso.local
```

### Reparo de conta de máquina no domínio

```powershell
# Detecção automática de domínio e DC:
.\active-directory\Testa-Repara-ContaMaquinaAD.ps1

# Com domínio e DC específicos:
.\active-directory\Testa-Repara-ContaMaquinaAD.ps1 `
    -DomainFqdn contoso.local -PreferredDc DC01

# Com DNS específico:
.\active-directory\Testa-Repara-ContaMaquinaAD.ps1 `
    -DomainFqdn contoso.local -DnsServers 192.168.1.7
```

---

## Pasta de relatórios

Caminho padrão: `C:\WBA\Relatorios\<Script>\<timestamp>\`

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force

# Definir pasta padrão permanente:
Set-ToolkitReportsRoot -Path "D:\Relatorios"

# Consultar pasta atual:
Get-ToolkitReportsRoot
```

---

## Gerar portal de documentação HTML

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force

# Portal completo (portal operacional + referência técnica):
Export-ToolkitDocumentation -Mode All -Force
# Resultado em: .\docs\portal\index.html

# Somente portal operacional:
Export-ToolkitDocumentation -Mode Portal -Force
```
