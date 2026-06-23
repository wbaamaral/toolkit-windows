# configuration

Scripts de configuração e padronização de instalações Windows. Aplicam configurações de idioma, regionalização, fuso horário e preferências do sistema para garantir consistência entre estações de trabalho em ambientes corporativos brasileiros.

---

## Scripts

### `Configurar-Idioma-Regional.ps1`

**Função:** Padroniza o idioma de exibição, locale regional e fuso horário de instalações Windows 10/11 Pro+ para o padrão pt-BR.

**Principais ações:**

| Etapa | Ação |
|---|---|
| Pacote de idioma | Instala pt-BR via `LanguagePackManagement` (Win11/Win10 20H1+) com fallback para `Add-WindowsCapability` |
| Idioma de exibição | Define pt-BR como `WinUILanguageOverride` para o usuário atual |
| Locale regional | Configura cultura pt-BR (formatos de data, hora, moeda e separadores numéricos) |
| Locale do sistema | Define `WinSystemLocale` pt-BR (afeta programas não-Unicode) |
| Teclado | Adiciona layout ABNT2 (`0416:00010416`) como padrão |
| Localização geográfica | Define Brasil como localização (GeoID 32) |
| Propagação | Copia todas as configurações para a conta do sistema e perfil padrão de novos usuários via `intl.cpl` com XML de propagação |
| Fuso horário | Define o fuso via `Set-TimeZone` (padrão UTC-4, parametrizável) |
| Log | Salva transcrição completa em `C:\WBA\Relatorios\Configuration\<timestamp>\logs` ou em raiz definida por `-DiretorioSaida` |

**Parâmetros:**

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `-TimeZone` | `SA Western Standard Time` | ID do fuso horário Windows (UTC-4) |
| `-Silent` | — | Modo silencioso sem prompts — para automação, GPO, SCCM |
| `-NoReboot` | — | Não reinicia ao final |
| `-ListTimeZones` | — | Lista os fusos horários do Brasil e encerra |
| `-Help` | — | Exibe ajuda completa |
| `-Version` | — | Exibe versão do script |
| `-DiretorioSaida` | `ReportsRoot` ou `C:\WBA\Relatorios` | Raiz de relatórios; o script cria `Configuration\<timestamp>\logs` |

**Fusos horários brasileiros disponíveis** (use o valor exato em `-TimeZone`):

| ID Windows | UTC | Regiões cobertas |
|---|---|---|
| `E. South America Standard Time` | UTC-3 | Brasília/DF, SP, RJ, MG, GO, PR, SC, RS |
| `SA Eastern Standard Time` | UTC-3 | Fortaleza/CE, Recife/PE, Belém/PA, Nordeste |
| `Tocantins Standard Time` | UTC-3 | Palmas/TO, Araguaína/TO |
| `Bahia Standard Time` | UTC-3 | Salvador/BA |
| `SA Western Standard Time` *(padrão)* | UTC-4 | Manaus/AM, Porto Velho/RO, Cuiabá/MT, Campo Grande/MS |
| `SA Pacific Standard Time` | UTC-5 | Rio Branco/AC, extremo oeste do AM |

**Uso básico:**

```powershell
# Interativo com fuso padrão UTC-4
.\Configurar-Idioma-Regional.ps1

# Automação/GPO silenciosa sem reboot (UTC-4)
.\Configurar-Idioma-Regional.ps1 -Silent -NoReboot

# Brasília (UTC-3), silencioso
.\Configurar-Idioma-Regional.ps1 -Silent -NoReboot -TimeZone "E. South America Standard Time"

# Listar fusos do Brasil
.\Configurar-Idioma-Regional.ps1 -ListTimeZones
```

> **Nota:** Uma reinicialização é necessária para que o idioma de exibição seja aplicado completamente na interface gráfica. O locale regional e o fuso horário entram em vigor imediatamente.

**Requisitos:** Administrador local. Windows 10 Pro 21H2+ ou Windows 11 Pro. PowerShell 5.1+. Acesso à internet para download do pacote de idioma quando ausente.

**Log:** `C:\WBA\Relatorios\Configuration\<timestamp>\logs\<timestamp>-Configurar-Idioma-Regional.log` ou `<DiretorioSaida>\Configuration\<timestamp>\logs\...`
