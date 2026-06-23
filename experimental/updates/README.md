# updates

Scripts para atualização do sistema operacional e pacotes de software instalados. Projetados para ambientes corporativos onde ferramentas externas como PSWindowsUpdate ou WinGet podem não estar disponíveis, utilizando apenas componentes nativos do Windows.

Atalho oficial do MVP:

```powershell
.\scripts\atualizar-windows.ps1
```

---

## Scripts

### `upgrade-windows.ps1`

**Função:** Atualização básica e conservadora do Windows 10 Pro via componentes nativos e Chocolatey.

**Principais ações:**

| Etapa | Ação |
|---|---|
| Windows Update nativo | Aciona varredura e instalação via `UsoClient StartScan` e `UsoClient StartInstall` |
| Chocolatey | Executa `choco upgrade all -y` quando o Chocolatey estiver instalado |
| Relatório | Exibe resultado de cada etapa com status de sucesso ou falha |
| Log | Salva transcrição completa em `C:\WBA\Relatorios\Updates\<timestamp>\logs` ou em raiz definida por `-DiretorioSaida` |

> **Nota:** O script não instala o PSWindowsUpdate, não instala o WinGet, não força reinicialização automática e não instala novos gerenciadores de pacotes — utiliza somente o que já está presente no sistema.

**Parâmetros:**

| Parâmetro | Descrição |
|---|---|
| `-Help` | Exibe ajuda |
| `-Version` | Exibe versão do script |
| `-NoWindowsUpdate` | Não aciona o Windows Update nativo |
| `-NoChocolatey` | Não executa atualização via Chocolatey |
| `-NoRebootWarning` | Suprime aviso de reinicialização ao final |
| `-PauseAtEnd` | Aguarda tecla antes de encerrar (útil em execução manual) |
| `-DiretorioSaida` | Define uma raiz personalizada para os logs; o script cria `Updates\<timestamp>\logs` |

**Uso básico:**

```powershell
# Execução padrão (ambas as fontes de atualização)
.\upgrade-windows.ps1

# Apenas Windows Update, sem Chocolatey
.\upgrade-windows.ps1 -NoChocolatey

# Apenas Chocolatey, sem Windows Update
.\upgrade-windows.ps1 -NoWindowsUpdate

# Automação silenciosa (sem pausa, sem aviso de reboot)
.\upgrade-windows.ps1 -NoRebootWarning
```

**Requisitos:** Administrador local. Windows 10. PowerShell 5.1+. Chocolatey opcional.

**Log:** `C:\WBA\Relatorios\Updates\<timestamp>\logs\<timestamp>-upgrade-windows.log` ou `<DiretorioSaida>\Updates\<timestamp>\logs\...`
