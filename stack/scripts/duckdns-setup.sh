#!/usr/bin/env bash
# Phase 3 - free domain. Register the subdomain at https://www.duckdns.org first
# (GitHub/Google login, no card), then run:
#   bash duckdns-setup.sh <subdomain> <token>
# Installs a 5-minute cron refresh so the record follows the VM's IP.
set -euo pipefail

SUB="${1:?usage: duckdns-setup.sh <subdomain> <token>}"
TOKEN="${2:?usage: duckdns-setup.sh <subdomain> <token>}"

mkdir -p ~/duckdns
cat > ~/duckdns/duck.sh <<EOF
echo url="https://www.duckdns.org/update?domains=${SUB}&token=${TOKEN}&ip=" | curl -k -o ~/duckdns/duck.log -K -
EOF
chmod 700 ~/duckdns/duck.sh

bash ~/duckdns/duck.sh
echo "DuckDNS response: $(cat ~/duckdns/duck.log)"   # expect: OK

if crontab -l 2>/dev/null | grep -qF 'duckdns/duck.sh'; then
  echo "cron entry already present"
else
  (crontab -l 2>/dev/null; echo "*/5 * * * * ~/duckdns/duck.sh >/dev/null 2>&1") | crontab -
  echo "cron entry added"
fi

echo
echo "Waiting for DNS to resolve (Let's Encrypt will fail otherwise)..."
for i in $(seq 1 30); do
  ip=$(dig +short "${SUB}.duckdns.org" | tail -1)
  if [[ -n "$ip" ]]; then
    echo "${SUB}.duckdns.org -> $ip"
    public=$(curl -s https://api.ipify.org || true)
    [[ -n "$public" && "$ip" != "$public" ]] && echo "WARNING: VM public IP is $public - they do not match yet."
    exit 0
  fi
  echo "  not resolving yet, retry $i/30"
  sleep 10
done
echo "Still not resolving after 5 minutes. Check the DuckDNS dashboard before continuing."
exit 1
