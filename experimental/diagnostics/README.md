# diagnostics

Scripts de diagnóstico de conectividade e saúde do ambiente de rede. Executam sequências estruturadas de testes com coleta de evidências, exibindo resultados claros por etapa para auxiliar na identificação e localização de falhas.

---

## Scripts

### `Diagnostico-Driver-Grafico.ps1`

**Função:** Coleta evidências de travamentos gráficos, tela preta, falhas do DWM, TDR, WHEA, Kernel-Power e erros
relacionados a driver de vídeo.

**Principais ações:**

| Etapa | O que verifica |
|---|---|
| GPU e driver | Controladores de vídeo, versão/data do driver, assinatura e INF |
| Monitores | Monitores detectados, fabricante, serial e estado ativo |
| Eventos | Logs System/Application com Display, DWM, DirectX, WHEA, BugCheck e Kernel-Power |
| Processos | Processos ligados a aceleração gráfica, como DWM, Explorer, navegadores, Teams e WebView2 |
| Energia | Plano ativo, estados de suspensão e inicialização rápida |
| TDR | Chaves de registro em `GraphicsDrivers` usadas em diagnóstico de travamentos de vídeo |
| Evidências | TXT, JSON, HTML opcional, DXDiag opcional e exportação EVTX opcional |

**Parâmetros:**

| Parâmetro | Descrição |
|---|---|
| `-Modo` | `Diagnostico` ou `Assistido`; o modo assistido ativa HTML, DXDiag e EVTX |
| `-Dias` | Janela retroativa de eventos, padrão 7 dias |
| `-MaxEventos` | Limite de eventos lidos antes do filtro local |
| `-GerarHtml` | Gera relatório HTML local/autocontido |
| `-ExportarEvtx` | Exporta logs `System.evtx` e `Application.evtx` para `logs` |
| `-ColetarDxDiag` | Executa `dxdiag /t` e salva em `logs\dxdiag.txt` |
| `-AbrirRelatorio` | Abre o relatório gerado ao final |
| `-DiretorioSaida` | Raiz de relatórios; o script cria `Diagnostics\<timestamp>` |

**Uso básico:**

```powershell
# Diagnóstico seguro, sem alterações no sistema
.\Diagnostico-Driver-Grafico.ps1

# Diagnóstico com relatório HTML
.\Diagnostico-Driver-Grafico.ps1 -GerarHtml

# Coleta assistida com HTML, DXDiag e EVTX
.\Diagnostico-Driver-Grafico.ps1 -Modo Assistido
```

**Saída:** `C:\WBA\Relatorios\Diagnostics\<timestamp>\` ou `<DiretorioSaida>\Diagnostics\<timestamp>\`.

**Requisitos:** Windows 10/11. PowerShell 5.1+. Executar como administrador é recomendado para acesso completo a
eventos e inventário de dispositivos.

### `Testar-Conectividade-Internet.ps1`

**Função:** Invólucro operacional do módulo `WbaToolkit.Networking` para diagnóstico completo e sequencial de
conectividade com a internet.

**Principais ações:**

As etapas são executadas em sequência obrigatória — uma etapa bloqueada impede a execução das posteriores, isolando com precisão a camada da falha.

| Etapa | Camada | O que verifica |
|---|---|---|
| 1 | Rede local | Adaptador ativo, endereço IP, gateway padrão configurado e servidores DNS configurados |
| 2 | IP direto | Ping para `8.8.8.8`, `8.8.4.4`, `1.1.1.1` e `9.9.9.9` sem depender de DNS |
| 3 | DNS | Resolução de nomes para `google.com`, `microsoft.com`, `cloudflare.com` e `www.msftconnecttest.com` |
| 4 | Domínios | Ping e teste de porta TCP 443 para hosts públicos validando conectividade de ponta a ponta |

**Parâmetros:**

| Parâmetro | Descrição |
|---|---|
| `-Detalhado` | Exibe informações adicionais em cada teste (IPs resolvidos, latências individuais) |

**Uso básico:**

```powershell
# Diagnóstico padrão
.\Testar-Conectividade-Internet.ps1

# Com informações detalhadas
.\Testar-Conectividade-Internet.ps1 -Detalhado
```

**Saída:** Relatório em tela com status por teste, resumo final e bloqueio quando a rede local impede a continuação.

**Requisitos:** Não requer administrador. Windows 10+. PowerShell 5.1+.

### Teste direcionado por alvo, protocolo e portas

O módulo `WbaToolkit.Networking` também permite testar um destino específico com protocolo e portas definidos pelo operador.

```powershell
Import-Module .\modules\WbaToolkit.Networking\WbaToolkit.Networking.psd1 -Force

# Wizard interativo
Invoke-TargetConnectivityWizard

# TCP em portas específicas
$report = Invoke-TargetConnectivityTest -TargetAddress 192.168.5.10 -Protocol TCP -PortSpec '80,443,3389'
Show-ConnectivityReport -Report $report

# TCP, UDP e ICMP no mesmo alvo
$report = Invoke-TargetConnectivityTest -TargetAddress 192.168.5.10 -Protocol All -PortSpec '53,80,443,8000-8010'
Show-ConnectivityReport -Report $report
```
