#!/usr/bin/env bash
# Phase 7 - the checks that can be automated. Run on the VM:
#   bash verify.sh <domain>              # public mode
#   bash verify.sh --tailscale <domain>  # private mode
# Mode is auto-detected from ~/n8n if you omit the flag.
set -uo pipefail

MODE=""
if [[ "${1:-}" == "--tailscale" ]]; then MODE=tailscale; shift
elif [[ "${1:-}" == "--public" ]]; then MODE=public; shift; fi

DOMAIN="${1:?usage: verify.sh [--tailscale|--public] <domain>}"
[[ -n "$MODE" ]] || { if [[ -f "$HOME/n8n/Caddyfile" ]]; then MODE=public; else MODE=tailscale; fi; }

pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ok    $1"; pass=$((pass+1)); else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
running() { (cd ~/n8n && docker compose ps --status running --format '{{.Name}}' | wc -l); }

echo "Checks for $DOMAIN ($MODE mode)"
check "n8n answers on localhost"  "curl -s -o /dev/null -w '%{http_code}' localhost:5678 | grep -qE '^(200|401|302)$'"
check "swap active"               "swapon --show | grep -q /swapfile"
check "backup cron installed"     "crontab -l | grep -q backup-n8n"

if [[ $MODE == public ]]; then
  check "both containers Up"      "[ \$(running) -eq 2 ]"
  check "DNS resolves"            "[ -n \"\$(dig +short $DOMAIN)\" ]"
  check "DNS matches public IP"   "[ \"\$(dig +short $DOMAIN | tail -1)\" = \"\$(curl -s https://api.ipify.org)\" ]"
  check "HTTPS with valid cert"   "curl -sSf -o /dev/null https://$DOMAIN/"
  check "duckdns cron installed"  "crontab -l | grep -q duckdns"
  hint="references/troubleshooting.md sections 1 and 2 cover almost all of these."
else
  check "n8n container Up"        "[ \$(running) -eq 1 ]"
  check "not listening publicly"  "! ss -ltn | grep -qE '0\.0\.0\.0:5678|\[::\]:5678'"
  check "tailscale connected"     "tailscale status >/dev/null"
  check "tailscale serve active"  "sudo tailscale serve status | grep -q 5678"
  check "HTTPS with valid cert"   "curl -sSf -o /dev/null https://$DOMAIN/"
  hint="references/troubleshooting.md section 4 covers the Tailscale path."
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ] || echo "$hint"
echo
echo "Still to check by hand:"
echo "  - owner account created, login works"
echo "  - a Schedule-triggered workflow fires with the browser closed"
echo "  - an AI Agent node returns a completion from the free provider"
echo "  - sudo reboot, wait 2 min, site returns by itself"
if [[ $MODE == public ]]; then
  echo "  - a Webhook production URL responds from mobile data, not home wifi"
  echo "  - site loads on the phone; add to home screen"
else
  echo "  - site loads on the phone with the Tailscale app on and connected"
  echo "  - phone still reaches it on mobile data, not just home wifi"
  echo "  - webhooks: inbound calls from outside services need tailscale funnel"
fi
exit $fail
