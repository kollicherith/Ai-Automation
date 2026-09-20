#!/usr/bin/env bash
# Phase 1 - "Out of host capacity" retry loop. Run this on your own machine
# (or any always-on box), NOT on the VM you are trying to create.
#
# Setup:
#   1. Install and configure the OCI CLI:
#      https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm
#   2. Attempt the launch once in the Console, and on the failed attempt use
#      "Save as stack"/the CLI preview to capture the exact launch JSON.
#   3. Save it next to this script as launch.json.
#   4. bash launch-retry.sh
#
# Capacity is released in bursts, often at odd hours UTC. Hours to a few days is
# normal. Do NOT open a second Oracle account to get around it - that is against
# the terms and gets both banned. If it never frees up, try a smaller shape
# (2 OCPU / 12 GB succeeds far more often and is ample for n8n) or another
# availability domain; see references/troubleshooting.md section 3.
set -uo pipefail

JSON="${1:-launch.json}"
INTERVAL="${2:-300}"
[[ -f "$JSON" ]] || { echo "missing $JSON - see the header of this script" >&2; exit 1; }

attempt=0
while true; do
  attempt=$((attempt+1))
  echo "$(date -Is) attempt $attempt"
  if oci compute instance launch --from-json "file://$JSON"; then
    echo "$(date -Is) launched after $attempt attempt(s)"
    break
  fi
  echo "$(date -Is) capacity unavailable, retrying in ${INTERVAL}s"
  sleep "$INTERVAL"
done
