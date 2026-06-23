# Guia Rápido do Operador — WBA Windows Toolkit

Autor: **wbaamaral** — v1.2.0

Manual completo: [`manual-operador-wba-windows-toolkit.md`](../manual-operador-wba-windows-toolkit.md)
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

## Scripts operacionais

### Diagnóstico de rede

```powershell
# Diagnóstico padrão:
.\experimental\diagnostics\networking\Testar-Conectividade-Internet.ps1

# Com detalhes adicionais no console:
.\experimental\diagnostics\networking\Testar-Conectividade-Internet.ps1 -Detalhado
```

### Diagnóstico de disco (HD100)

```powershell
# Diagnóstico padrão:
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1

# Com relatório HTML:
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -GerarHtml

# Modo assistido (oferece ações de reparo):
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -Modo Assistido -GerarHtml

# Simulação sem executar comandos externos:
.\experimental\maintenance\Diagnostico-Reparo-HD100.ps1 -DryRun
```

### Diagnóstico de driver gráfico

```powershell
# Diagnóstico padrão:
.\experimental\diagnostics\Diagnostico-Driver-Grafico.ps1

# Com relatório HTML:
.\experimental\diagnostics\Diagnostico-Driver-Grafico.ps1 -GerarHtml

# Coleta completa (HTML + DXDiag + exportação de log de eventos):
.\experimental\diagnostics\Diagnostico-Driver-Grafico.ps1 -GerarHtml -ColetarDxDiag -ExportarEvtx
```

### Diagnóstico de memória

```powershell
# Top 10 consumidores de RAM (padrão):
.\experimental\diagnostics\Diagnostico-Memoria.ps1

# Top 20 processos:
.\experimental\diagnostics\Diagnostico-Memoria.ps1 -Top 20

# Listar todos os processos:
.\experimental\diagnostics\Diagnostico-Memoria.ps1 -Todos

# Com relatório HTML:
.\experimental\diagnostics\Diagnostico-Memoria.ps1 -GerarHtml
```

### Verificar atualizações de hardware

```powershell
# Diagnóstico completo (BIOS + drivers + Windows Update):
.\experimental\diagnostics\Verificar-Atualizacoes-Hardware.ps1

# Com relatório HTML:
.\experimental\diagnostics\Verificar-Atualizacoes-Hardware.ps1 -GerarHtml

# Somente BIOS:
.\experimental\diagnostics\Verificar-Atualizacoes-Hardware.ps1 -SkipDrivers

# Somente drivers:
.\experimental\diagnostics\Verificar-Atualizacoes-Hardware.ps1 -SkipBios
```

### Inventário de hardware/software

```powershell
# Inventário completo (HTML + PDF quando Chrome ou Edge disponível):
.\experimental\inventory\Inventario-Hardware-Software.ps1

# Sem PDF (somente HTML):
.\experimental\inventory\Inventario-Hardware-Software.ps1 -NaoPDF

# Somente resumo de hardware e drivers:
.\experimental\inventory\Inventario-Hardware-Software.ps1 -SomenteHardwareDrivers

# Inventário completo + resumo de hardware/drivers:
.\experimental\inventory\Inventario-Hardware-Software.ps1 -GerarResumoHardwareDrivers
```

### Gerenciar inicialização

```powershell
# Somente visualização (padrão):
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1

# Com relatório HTML:
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1 -GerarHtml

# Modo assistido (permite desabilitar/habilitar entradas):
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido

# Simulação sem alterar o sistema:
.\experimental\maintenance\Gerenciar-Inicializacao-Windows.ps1 -Modo Assistido -DryRun
```

### Limpeza do Windows

```powershell
# Limpeza conservadora sem reiniciar (recomendado):
.\experimental\maintenance\limpeza-windows.ps1 -NoReboot

# Somente reparar sistema (SFC + DISM):
.\experimental\maintenance\limpeza-windows.ps1 -RepararSistema -NoReboot

# Limpeza sem SFC/DISM:
.\experimental\maintenance\limpeza-windows.ps1 -NoSfc -NoReboot

# Liberar espaço do hiberfil.sys (desativa hibernação):
.\experimental\maintenance\limpeza-windows.ps1 -DisableHibernation -NoReboot
```

### Limpeza do WinSxS (Component Store)

```powershell
# Diagnóstico somente leitura (padrão):
.\experimental\maintenance\Limpeza-WinSxS.ps1

# Relatório em JSON:
.\experimental\maintenance\Limpeza-WinSxS.ps1 -Modo Relatorio

# Relatório em JSON e HTML:
.\experimental\maintenance\Limpeza-WinSxS.ps1 -Modo Relatorio -GerarHtml

# Limpeza assistida (solicita confirmação):
.\experimental\maintenance\Limpeza-WinSxS.ps1 -Modo Limpeza

# Simulação da limpeza sem alterar nada:
.\experimental\maintenance\Limpeza-WinSxS.ps1 -Modo Limpeza -DryRun
```

### Backup e restauração de drivers

```powershell
# Backup interativo (padrão):
.\experimental\maintenance\Backup-Restaurar-Drivers.ps1

# Simulação de backup:
.\experimental\maintenance\Backup-Restaurar-Drivers.ps1 -DryRun

# Restauração interativa com relatório HTML:
.\experimental\maintenance\Backup-Restaurar-Drivers.ps1 -Modo Restore -GerarHtml

# Path de relatório/backup customizado:
.\experimental\maintenance\Backup-Restaurar-Drivers.ps1 -Path "D:\Backup\Drivers"
```

### Preparar imagem corporativa (sysprep)

```powershell
# Simulação obrigatória antes de qualquer execução:
.\experimental\maintenance\Preparar-Imagem-Windows.ps1 -ApenasDryRun

# Aplicar tweaks sem iniciar sysprep:
.\experimental\maintenance\Preparar-Imagem-Windows.ps1 -SemSysprep

# Execução completa (tweaks de perfil Default + sysprep):
.\experimental\maintenance\Preparar-Imagem-Windows.ps1
```

### Configurar idioma e região

```powershell
# Configuração padrão (pt-BR, UTC-4):
.\experimental\configuration\Configurar-Idioma-Regional.ps1

# Modo silencioso sem reboot (automação, GPO, SCCM):
.\experimental\configuration\Configurar-Idioma-Regional.ps1 -Silent -NoReboot

# Fuso de Brasília (UTC-3):
.\experimental\configuration\Configurar-Idioma-Regional.ps1 -TimeZone "E. South America Standard Time"

# Listar fusos disponíveis do Brasil:
.\experimental\configuration\Configurar-Idioma-Regional.ps1 -ListTimeZones
```

### Análise de espaço em disco

```powershell
# Varrer todos os volumes locais:
.\experimental\utilities\Analise-Espaco-Disco.ps1

# Varrer somente C::
.\experimental\utilities\Analise-Espaco-Disco.ps1 -Drive C

# Sem conversão para PDF:
.\experimental\utilities\Analise-Espaco-Disco.ps1 -NaoPDF
```

### Remover perfis inativos

```powershell
# Simulação — lista o que seria removido sem alterar nada:
.\experimental\utilities\Remover-Perfis-Inativos.ps1 -DryRun

# Modo interativo (padrão):
.\experimental\utilities\Remover-Perfis-Inativos.ps1

# Automático (remove órfãos e inativos sem confirmação):
.\experimental\utilities\Remover-Perfis-Inativos.ps1 -Silent
```

### Atualizar Windows

```powershell
# Atualização completa (Windows Update + Chocolatey):
.\experimental\updates\upgrade-windows.ps1 -PauseAtEnd

# Somente Windows Update:
.\experimental\updates\upgrade-windows.ps1 -NoChocolatey -PauseAtEnd

# Somente Chocolatey:
.\experimental\updates\upgrade-windows.ps1 -NoWindowsUpdate -PauseAtEnd
```

### Diagnóstico de GPO

```powershell
# Detecção automática de domínio e DC:
.\experimental\active-directory\Diagnostico-GPO-Client.ps1

# Somente leitura com DC específico:
.\experimental\active-directory\Diagnostico-GPO-Client.ps1 -DCName DC01 -SkipReparo

# Com FQDN do domínio informado:
.\experimental\active-directory\Diagnostico-GPO-Client.ps1 -DomainFQDN contoso.local
```

### Reparo de conta de máquina no domínio

```powershell
# Detecção automática de domínio e DC:
.\experimental\active-directory\Testa-Repara-ContaMaquinaAD.ps1

# Com domínio e DC específicos:
.\experimental\active-directory\Testa-Repara-ContaMaquinaAD.ps1 `
    -DomainFqdn contoso.local -PreferredDc DC01

# Com DNS específico:
.\experimental\active-directory\Testa-Repara-ContaMaquinaAD.ps1 `
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
