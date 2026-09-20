#!/usr/bin/env bash
# Phase 7 - the checks that can be automated. Run on the VM:
#   bash verify.sh <domain>
# The rest of Phase 7 (owner account, schedule trigger fires, webhook from mobile
# data, AI Agent completion, reboot test, phone browser) is manual by nature.
set -uo pipefail

DOMAIN="${1:?usage: verify.sh <domain>}"
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ok    $1"; pass=$((pass+1)); else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

echo "Checks for $DOMAIN"
check "both containers Up"        "[ \$(cd ~/n8n && docker compose ps --status running --format '{{.Name}}' | wc -l) -eq 2 ]"
check "n8n answers on localhost"  "curl -sf -o /dev/null localhost:5678 || curl -s -o /dev/null -w '%{http_code}' localhost:5678 | grep -qE '^(200|401|302)$'"
check "DNS resolves"              "[ -n \"\$(dig +short $DOMAIN)\" ]"
check "DNS matches public IP"     "[ \"\$(dig +short $DOMAIN | tail -1)\" = \"\$(curl -s https://api.ipify.org)\" ]"
check "HTTPS with valid cert"     "curl -sSf -o /dev/null https://$DOMAIN/"
check "swap active"               "swapon --show | grep -q /swapfile"
check "backup cron installed"     "crontab -l | grep -q backup-n8n"
check "duckdns cron installed"    "crontab -l | grep -q duckdns"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ] || echo "See references/troubleshooting.md - sections 1 and 2 cover almost all of these."
echo
echo "Still to check by hand:"
echo "  - owner account created, login works"
echo "  - a Schedule-triggered workflow fires with the browser closed"
echo "  - a Webhook production URL responds from mobile data, not home wifi"
echo "  - an AI Agent node returns a completion from the free provider"
echo "  - sudo reboot, wait 2 min, site returns by itself"
echo "  - site loads on the phone; add to home screen"
exit $fail
