#!/usr/bin/env bash
# Designed, not tested. Static check, no Azure calls: every gate variable must default to false.
# Tolerant of whitespace so that `terraform fmt` realignment does not break it.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for g in deploy_route_server deploy_nvas deploy_vpn_gateway; do
  if ! tr -s ' \t\n' ' ' < variables.tf | grep -Eq "variable \"$g\" \{[^}]*default *= *false"; then
    echo "FAIL: $g does not default to false"; fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "OK: all gates default to false"
exit "$fail"
