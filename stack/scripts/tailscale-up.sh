#!/usr/bin/env bash
# Phase 3, private mode - join the VM to your tailnet and report its HTTPS name.
# Replaces DuckDNS entirely. Run on the VM:
#   bash tailscale-up.sh [machine-name]      # default: ck-automation
# It prints a login URL; open it, sign in, come back.
set -euo pipefail

MACHINE="${1:-ck-automation}"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "== Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscale status >/dev/null 2>&1; then
  echo "== Authenticating as '$MACHINE' - open the URL below, sign in, then return here"
  # --hostname fixes the machine name, so the .ts.net address is predictable
  # rather than whatever Oracle called the instance.
  sudo tailscale up --hostname="$MACHINE"
fi

HOSTNAME_TS=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[[ -n "$HOSTNAME_TS" ]] || { echo "Could not read the tailnet DNS name. Is MagicDNS enabled?" >&2; exit 1; }

echo
echo "== This VM is on your tailnet as:"
echo "   $HOSTNAME_TS"
echo

# Provisioning a cert is the step that exposes a missing tailnet setting, and the
# error Tailscale returns for it is not obvious. Surface it now, not at deploy.
echo "== Checking HTTPS certificates are enabled for your tailnet"
if sudo tailscale cert "$HOSTNAME_TS" >/dev/null 2>&1; then
  echo "   ok - certificate issued"
else
  cat >&2 <<MSG

   FAILED. Almost always this one setting:

     Tailscale admin console > Settings > Features > HTTPS Certificates > Enable
     (MagicDNS must be on too - https://login.tailscale.com/admin/dns)

   Enable it, then re-run this script.
MSG
  exit 1
fi

echo
echo "Next: bash scripts/deploy.sh --tailscale $HOSTNAME_TS Europe/Dublin"
