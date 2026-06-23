# active-directory

Scripts de diagnóstico e reparo de problemas em ambientes Active Directory. Focados no lado cliente: verificam canal seguro, conectividade com controladores de domínio, aplicação de GPO, sincronização de horário Kerberos e integridade da conta de máquina no domínio.

Fluxo oficial atual do MVP:

```powershell
.\scripts\diagnosticar-ad-cliente.ps1
```

---

## Scripts

### `Diagnostico-GPO-Client.ps1`

**Função:** Diagnóstico de problemas de aplicação de Política de Grupo (GPO) em clientes Windows ingressados no domínio.

**Principais ações:**

| Teste | O que verifica |
|---|---|
| 1 — Canal seguro | `nltest /sc_query` — valida o secure channel com o DC |
| 2 — Conectividade com o DC | Ping, porta LDAP 389 e SMB 445 para o controlador de domínio |
| 3 — SYSVOL / NETLOGON | Acesso ao compartilhamento SYSVOL e NETLOGON do DC |
| 4 — Serviços essenciais | Status de `gpsvc`, `Netlogon`, `Dnscache` e `W32Time` |
| 5 — Sincronização de horário | `w32tm /query /status` — valida NTP/Kerberos |
| 6 — GPOs aplicadas | `gpresult /r` — lista GPOs efetivas para usuário e computador |
| 7 — Eventos de GPO | Busca erros e avisos no Event Log dos últimos canais de GPO (24h) |
| 8 — gpupdate /force | Força reaplicação das políticas (com confirmação interativa) |
| 9 — RSoP | Resultant Set of Policy com análise de CSEs (Client-Side Extensions) |
| 10 — Herança de GPO | Hierarquia de OUs e herança de políticas (requer RSAT instalado) |

**Parâmetros:**

| Parâmetro | Descrição |
|---|---|
| `-DomainFQDN` | FQDN do domínio (auto-detectado se omitido) |
| `-DCName` | Nome ou IP do DC preferencial (auto-detectado se omitido) |
| `-SkipReparo` | Executa apenas leitura; não oferece ações de reparo |
| `-DiretorioSaida` | Raiz de relatórios; o script cria `ActiveDirectory\<timestamp>` |

**Uso básico:**

```powershell
# Diagnóstico completo (auto-detecção de domínio e DC)
.\Diagnostico-GPO-Client.ps1

# Especificando domínio e DC
.\Diagnostico-GPO-Client.ps1 -DomainFQDN "empresa.local" -DCName "DC01"

# Apenas leitura, sem opções de reparo
.\Diagnostico-GPO-Client.ps1 -SkipReparo
```

**Requisitos:** Administrador local. Máquina ingressada no domínio. PowerShell 5.1+.

**Saída:** `C:\WBA\Relatorios\ActiveDirectory\<timestamp>\GPOResult-<timestamp>.html` e `logs\DiagGPO-<timestamp>.log`, ou `<DiretorioSaida>\ActiveDirectory\<timestamp>\...`

---

### `Testa-Repara-ContaMaquinaAD.ps1`

**Função:** Diagnóstico e reparo de falhas de conta de máquina e canal seguro em domínio Active Directory.

**Principais ações:**

| Teste | O que verifica / executa |
|---|---|
| 0 — Contexto | Coleta nome do computador, domínio, usuário logado e DC atual |
| 1 — DNS do cliente | Servidores DNS configurados e resolução de `_ldap._tcp.<domínio>` |
| 2 — Registros SRV do AD | Resolução dos registros SRV necessários para localização do DC |
| 3 — Descoberta do DC | `nltest /dsgetdc` — localiza e valida o controlador de domínio |
| 4 — Portas essenciais | Conectividade TCP para portas 53, 88 (Kerberos), 135, 389 (LDAP), 445, 464, 3268 |
| 5 — Sincronização de horário | `w32tm /query` — valida sincronização NTP (crítica para Kerberos) |
| 6 — Ingresso no domínio | Confirma que a máquina está ingressada e a conta existe no AD |
| 7 — Secure Channel | `nltest /sc_query` e `nltest /sc_verify` — testa e verifica o canal seguro |
| 8 — Tickets Kerberos | `klist` — lista e valida tickets Kerberos ativos |
| 9 — Reparo do Secure Channel | `Test-ComputerSecureChannel -Repair` com credencial de domínio |
| Opcional | `Reset-ComputerMachinePassword` e `Remove-Computer` (com confirmação) |

**Parâmetros:**

| Parâmetro | Descrição |
|---|---|
| `-DomainFqdn` | FQDN do domínio (auto-detectado se omitido) |
| `-DomainNetBIOS` | Nome NetBIOS do domínio (auto-detectado se omitido) |
| `-PreferredDc` | IP ou FQDN do DC preferencial para os testes |
| `-DnsServers` | Array de servidores DNS a serem testados |
| `-NoTranscript` | Não cria arquivo de log de transcrição |
| `-DiretorioSaida` | Raiz de relatórios; o script cria `ActiveDirectory\<timestamp>\logs` |

**Uso básico:**

```powershell
# Diagnóstico completo (auto-detecção)
.\Testa-Repara-ContaMaquinaAD.ps1

# Especificando DC e DNS
.\Testa-Repara-ContaMaquinaAD.ps1 -PreferredDc "192.168.1.10" -DnsServers @("192.168.1.10","192.168.1.11")

# Sem geração de log
.\Testa-Repara-ContaMaquinaAD.ps1 -NoTranscript
```

> **Atenção:** O script oferece ações de reparo interativas que **reingressam a máquina no domínio** ou **resetam a senha da conta de máquina**. Nenhuma ação destrutiva é executada sem confirmação explícita do operador.

**Requisitos:** Administrador local. Máquina ingressada no domínio. Credenciais de domínio com permissão de reset de conta de máquina para reparo. PowerShell 5.1+.

**Log:** `C:\WBA\Relatorios\ActiveDirectory\<timestamp>\logs\AD-MachineAccount-Repair-<timestamp>.log` ou `<DiretorioSaida>\ActiveDirectory\<timestamp>\logs\...`
