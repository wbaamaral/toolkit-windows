#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== WBA Lab Docker — teste AD sem VMs ==="
echo "Toolkit: $TOOLKIT_ROOT"
echo ""

# 1) Sobe lab
echo "[1/4] Subindo samba-dc (wba.test) ..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
echo "Aguardando healthcheck do samba-dc (até 90s) ..."
timeout 120 bash -c 'until docker inspect --format="{{.State.Health.Status}}" wba-dc01 2>/dev/null | grep -q healthy; do sleep 2; echo -n "."; done; echo " healthy!"'

echo ""
echo "[2/4] DNS do cliente pwsh deve apontar para 172.20.0.10"
docker exec wba-pwsh-client cat /etc/resolv.conf | head -n 20 || true

echo ""
echo "[3/4] Teste DNS puro (dig + TCP) contra wba.test"
docker exec wba-pwsh-client bash -c 'apt-get update -qq && apt-get install -y -qq dnsutils 2>&1 | tail -n 5; echo "--- dig wba.test ---"; dig +short wba.test @172.20.0.10; echo "--- dig SRV _ldap._tcp.wba.test ---"; dig +short SRV _ldap._tcp.wba.test @172.20.0.10; echo "--- dig SRV _kerberos._tcp.wba.test ---"; dig +short SRV _kerberos._tcp.wba.test @172.20.0.10; echo "--- nc 389 ---"; timeout 2 bash -c "cat < /dev/null > /dev/tcp/172.20.0.10/389 && echo LDAP 389 OK || echo LDAP 389 FAIL"; echo "--- nc 445 ---"; timeout 2 bash -c "cat < /dev/null > /dev/tcp/172.20.0.10/445 && echo SMB 445 OK || echo SMB 445 FAIL"'

echo ""
echo "[4/4] Teste diagnosticar-ad-cliente.ps1 com MOCKS (sem Windows real)"
echo "      — cobre DNS + conectividade LDAP/SMB + lógica de correção (DryRun)"
docker exec wba-pwsh-client pwsh -NoProfile -File /workspace/toolkit/tests/lab-docker/Invoke-AdMockTest.ps1 -DomainFQDN wba.test -PreferredDc 172.20.0.10 -DnsServers 172.20.0.10

echo ""
echo "=== FIM ==="
echo "Para entrar no cliente interativo: docker exec -it wba-pwsh-client pwsh"
echo "Para rodar diagnóstico completo (com mocks): docker exec wba-pwsh-client pwsh -File /workspace/toolkit/tests/lab-docker/Invoke-AdMockTest.ps1"
echo "Para derrubar: docker compose -f $SCRIPT_DIR/docker-compose.yml down -v"
