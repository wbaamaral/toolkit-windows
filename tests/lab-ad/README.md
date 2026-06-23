# Lab de AD para testar os scripts de Active Directory

Ambiente mínimo para validar `experimental/active-directory/Diagnostico-GPO-Client.ps1` e
`experimental/active-directory/Testa-Repara-ContaMaquinaAD.ps1`, que exigem um domínio real.

## Topologia (2 VMs no mesmo segmento de rede)

| Papel | SO | Exemplo de IP | DNS |
|---|---|---|---|
| Controlador de Domínio (DC) | Windows Server 2019/2022/2025 | 192.168.4.10 | 127.0.0.1 (ele mesmo) |
| Cliente membro | Windows 10/11 (a VM atual serve) | 192.168.4.29 | 192.168.4.10 (o DC) |

Domínio do lab: **wba.test** / NetBIOS **WBA** (parametrizável nos scripts).

## Passo a passo

### No DC (Windows Server limpo, PowerShell elevado)

1. **Fase 1 — promover a DC** (a máquina reinicia ao final):
   ```powershell
   .\01-Provision-DC.ps1 -StaticIp 192.168.4.10 -Gateway 192.168.5.1
   ```
   - Vai pedir a senha do **DSRM**.

2. **Fase 2 — após o reboot, criar OU + usuário + GPO**:
   ```powershell
   .\02-Configure-DC.ps1
   ```
   - Cria: OU `WBA-Lab`, usuário `lab.operador`, GPO `WBA Lab - Baseline` linkada.

### No cliente membro (PowerShell elevado)

3. **Fase 3 — DNS + RSAT + ingresso no domínio** (reinicia ao final):
   ```powershell
   .\03-Join-Client.ps1 -DcIp 192.168.4.10
   ```
   - Vai pedir credencial de **Domain Admin** (`WBA\Administrator`).

## Rodando os scripts WBA (no cliente, já no domínio)

Faça logon como **usuário de domínio** (`WBA\lab.operador`) para o gpresult de usuário.

```powershell
# Diagnóstico de GPO / cliente
.\experimental\active-directory\Diagnostico-GPO-Client.ps1 -DomainFQDN wba.test -DCName DC01

# Teste/reparo da conta de máquina (leitura é segura)
.\experimental\active-directory\Testa-Repara-ContaMaquinaAD.ps1 -DomainFqdn wba.test -DomainNetBIOS WBA -PreferredDc DC01 -DnsServers 192.168.4.10
```

## Exercitando os caminhos de ERRO (para validar o reparo)

### A) Secure channel quebrado (Testa-Repara)
No **DC**, resete a conta de máquina do cliente:
```powershell
Reset-ADComputerAccount -Identity '<NOME-DO-CLIENTE>' -Server DC01
```
Depois, no **cliente**, rode o `Testa-Repara-ContaMaquinaAD.ps1` — ele deve detectar o
canal quebrado e oferecer/efetuar o reparo (`Reset-ComputerMachinePassword`, exige
credencial com direito de reset).

### B) Skew de tempo (checagem w32tm)
No **cliente**, desincronize o relógio para validar a detecção de offset:
```powershell
Set-Date (Get-Date).AddMinutes(20)   # reverter depois com w32tm /resync
```

## Privilégios necessários (resumo)

| Script | Contexto | Privilégio |
|---|---|---|
| Diagnostico-GPO-Client | usuário de domínio logado | leitura AD (qualquer auth) + elevação p/ gpupdate |
| Testa-Repara (leitura) | qualquer usuário do domínio | nenhum especial |
| Testa-Repara (reparo) | `-Credential` | Domain Admin ou direito de reset de conta |

## Notas
- O passo de DNS no cliente é o mais comum de esquecer — sem DNS apontando para o DC,
  nada de AD funciona.
- `Get-ADComputer` (usado pelo Diagnostico-GPO-Client) precisa do **RSAT AD PowerShell**,
  instalado pela fase 3.
