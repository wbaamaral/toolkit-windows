# Lab AD via Docker (sem VMs)

Alternativa ao `tests/lab-ad/` (que exige 2 VMs Windows) para validar `diagnosticar-ad-cliente.ps1` sem infraestrutura.

## O que roda

| Container | Imagem | Papel |
|---|---|---|
| `wba-dc01` | `instantlinux/samba-dc:latest` | Samba AD DC `wba.test` (`172.20.0.10`) — DNS + LDAP 389 + Kerberos 88 + SMB 445 |
| `wba-pwsh-client` | `mcr.microsoft.com/powershell:7.6-ubuntu-22.04` | Cliente `pwsh` com toolkit montado em `/workspace/toolkit`, DNS apontado ao Samba |

> Limitacão: Samba não é Windows Server. `Test-ComputerSecureChannel`/`Reset-ComputerMachinePassword`/`Get-ADComputer`/`gpresult`/`w32tm` são **mockados** em `Invoke-AdMockTest.ps1`. Valida fluxo de correção, DNS real e TCP 389/445. Para validação 100% Windows, use `tests/lab-ad/`.

## Pré-requisitos

- Docker 24+ e `docker compose` v2
- Linux host com `apparmor:unconfined` permitido (Samba precisa `SYS_ADMIN`)

## Uso rápido

```bash
cd wba-windows-toolkit/tests/lab-docker
./run-ad-test.sh
```

O script:

1. `docker compose up -d` + aguarda `healthcheck` (`samba-tool domain info`)
2. Testa `Resolve-DnsName wba.test` / `_ldap._tcp.wba.test` contra `172.20.0.10`
3. Testa TCP `389`/`445`
4. Roda `Invoke-AdMockTest.ps1` (3 cenários: Diagnostico, Assistido+Canal+Hora, Corrigir DryRun se existir)

Interativo:

```bash
docker exec -it wba-pwsh-client pwsh
# dentro do container:
Resolve-DnsName -Name wba.test -Server 172.20.0.10
Test-NetConnection 172.20.0.10 -Port 389
pwsh -File /workspace/toolkit/tests/lab-docker/Invoke-AdMockTest.ps1 -DomainFQDN wba.test -DnsServers 172.20.0.10
```

Derrubar:

```bash
docker compose down -v
```

## Como o mock funciona

`Invoke-AdMockTest.ps1` injeta no `global:` antes do `dot-source` do toolkit:

- `Test-ComputerSecureChannel` → retorna `$global:MockSecureChannelOk` (inicia `false` para simular quebra)
- `Reset-ComputerMachinePassword` → seta `true` e loga sucesso
- `Get-CimInstance Win32_ComputerSystem` → `cliente01.wba.test PartOfDomain=$true`
- `Get-DnsClientServerAddress` → retorna `172.20.0.10`
- `Invoke-ExternalCommand` (w32tm/nltest/gpresult) → respostas sintéticas
- `Sync-ComputerTime` → `{Success=$true SourceAfter=172.20.0.10}`

Assim o fluxo `Test-AdSecureChannel` → prompt `Deseja reparar?` → `Reset-ComputerMachinePassword` → re-teste é exercitado sem AD Windows.

## Para tornar ferramenta de correção completa

O harness já detecta se `diagnosticar-ad-cliente.ps1` tem `-CorrigirDns`/`-CorrigirTodos`/`-DryRun`. Quando você implementar a evolução para “ferramenta de correção” (DNS `Set-DnsClientServerAddress`, serviços `Set-Service`/`Start-Service`, etc.), o mesmo `lab-docker` validará com `-DryRun`.

## Troubleshooting

- `samba-dc` não fica healthy: `docker logs wba-dc01`, verificar `DOMAIN_PASS` atende complexidade, e `cap_add: SYS_ADMIN` + `apparmor:unconfined` no host.
- DNS não resolve no cliente: `docker exec wba-pwsh-client cat /etc/resolv.conf` deve listar `nameserver 172.20.0.10` primeiro.
- `Resolve-DnsName` timeout: samba leva ~60s para inicializar após `up`; `run-ad-test.sh` já aguarda healthcheck.
