#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities: lists rules and runs IP flow verify checks.
# Needs: az CLI signed in, the lab applied with deploy_vms = true, VMs running.
# Usage: ./scripts/verify.sh rules | effective | flows
set -euo pipefail

RG="${RG:-nsg19-rg}"
WEB_VM="${WEB_VM:-web-1}"
APP_VM="${APP_VM:-app-1}"
WEB_NIC="${WEB_NIC:-web-1-nic}"
APP_NIC="${APP_NIC:-app-1-nic}"

flow() { # name vm nic direction protocol local remote
  echo "== $1"
  az network watcher test-ip-flow -g "$RG" --vm "$2" --nic "$3" --direction "$4" --protocol "$5" --local "$6" --remote "$7" -o json
}

case "${1:-}" in
  rules)
    for n in nsg-web nsg-app nsg-pe nsg-app-nic; do
      echo "== $n"
      az network nsg rule list -g "$RG" --nsg-name "$n" --include-default -o table 2>/dev/null || echo "(not created)"
    done
    ;;
  effective)
    az network nic list-effective-nsg -g "$RG" -n "$APP_NIC" -o json
    az network nic list-effective-nsg -g "$RG" -n "$WEB_NIC" -o json
    ;;
  flows)
    # inbound at app-1: local is app-1, remote is the caller. The remote port is an arbitrary client port.
    flow "1 web to app 8080 (expect Allow by nsg-app allow-web-to-app-8080)" "$APP_VM" "$APP_NIC" Inbound TCP 10.30.2.10:8080 10.30.1.10:49152
    flow "2 web to app 22 (expect Deny by nsg-app deny-vnet-to-app)" "$APP_VM" "$APP_NIC" Inbound TCP 10.30.2.10:22 10.30.1.10:49153
    # outbound from app-1 to a public address: expect Deny by deny-app-to-internet
    flow "3 app to internet 443 (expect Deny)" "$APP_VM" "$APP_NIC" Outbound TCP 10.30.2.10:49154 198.51.100.80:443
    # outbound from web-1 to app-1 on 8080: expect Allow by nsg-web allow-web-to-app-8080
    flow "4 web outbound to app 8080 (expect Allow)" "$WEB_VM" "$WEB_NIC" Outbound TCP 10.30.1.10:49155 10.30.2.10:8080
    ;;
  *)
    echo "usage: $0 rules | effective | flows" >&2
    exit 2
    ;;
esac
