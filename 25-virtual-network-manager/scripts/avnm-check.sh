#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities: group members, committed configurations,
# peerings, effective security rules and a curl between the VMs. It never changes anything in Azure.
# Needs: az CLI signed in, the network-manager extension (az extension add -n virtual-network-manager),
# and for app/routes/rules the lab applied with deploy_vms = true.
# Usage: ./scripts/avnm-check.sh groups | committed | peerings | routes | rules | app
set -euo pipefail

P="${PREFIX:-avnm25}"
RG="${RG:-$P-rg}"
NM="${NM:-$P-avnm}"
REGIONS="${REGIONS:-westeurope}"
PORT="${APP_PORT:-8080}"

run_on() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv
}

case "${1:-}" in
  groups)
    for g in ng-spokes-static ng-prod-dynamic; do
      echo "== members of $g"
      az network manager group static-member list -g "$RG" --network-manager-name "$NM" --network-group-name "$g" \
        --query "[].{name:name, vnet:resourceId}" -o table 2>/dev/null || echo "(no such group, or it has no static members)"
    done
    ;;
  committed)
    echo "== active connectivity configurations"
    az network manager list-active-connectivity-config -g "$RG" --network-manager-name "$NM" --regions $REGIONS -o json
    echo "== active security admin rules"
    az network manager list-active-security-admin-rule -g "$RG" --network-manager-name "$NM" --regions $REGIONS -o json
    ;;
  peerings)
    for v in hub spoke-a spoke-b spoke-c; do
      echo "== peerings of $P-$v"
      az network vnet peering list -g "$RG" --vnet-name "$P-$v" --query "[].{name:name, state:peeringState}" -o table
    done
    if az group show -n "$RG-second" >/dev/null 2>&1; then
      echo "== peerings of $P-spoke-d"
      az network vnet peering list -g "$RG-second" --vnet-name "$P-spoke-d" --query "[].{name:name, state:peeringState}" -o table
    fi
    ;;
  routes)
    for vm in vm-a vm-b; do
      echo "== effective routes of $vm-nic"
      az network nic show-effective-route-table -g "$RG" -n "$vm-nic" \
        --query "value[].{prefix:addressPrefix[0], nextHopType:nextHopType, source:source}" -o table
    done
    ;;
  rules)
    echo "== effective security rules of vm-b-nic"
    az network nic list-effective-nsg -g "$RG" -n vm-b-nic -o json
    ;;
  app)
    echo "== vm-a calls vm-b on port $PORT (000 means no connection)"
    run_on vm-a "curl -s -m 5 -o /dev/null -w '%{http_code}' http://10.72.0.10:$PORT || true"
    echo "== vm-a calls vm-c on port $PORT"
    run_on vm-a "curl -s -m 5 -o /dev/null -w '%{http_code}' http://10.73.0.10:$PORT || true"
    ;;
  *)
    echo "usage: $0 groups | committed | peerings | routes | rules | app" >&2
    exit 2
    ;;
esac
