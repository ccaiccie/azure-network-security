#!/usr/bin/env bash
# Designed, not tested. Read-only: asks the Traffic Manager name every few seconds and prints a timestamp,
# the TTL and the answer, so you can see how long the answer takes to change after you stop a backend.
# Usage: TM_FQDN=<name> ./scripts/failover-timer.sh [seconds-between-queries] [number-of-queries]
set -euo pipefail

TM_FQDN="${TM_FQDN:?set TM_FQDN to the traffic_manager_fqdn output}"
STEP="${1:-5}"
COUNT="${2:-60}"

for _ in $(seq 1 "$COUNT"); do
  printf '%s  ' "$(date +%H:%M:%S)"
  dig +noall +answer +nocmd "$TM_FQDN" | awk '{printf "ttl=%s %s %s  ", $2, $4, $5}'
  echo
  sleep "$STEP"
done
