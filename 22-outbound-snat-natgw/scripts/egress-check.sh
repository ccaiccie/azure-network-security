#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities: shows the egress IP each VM reports,
# the effective routes, and the subnet attachments. It never changes anything in Azure.
# Needs: az CLI signed in, the lab applied with deploy_vms = true, VMs running.
# Usage: ./scripts/egress-check.sh ip | routes | attach | metrics
set -euo pipefail

RG="${RG:-snat22-rg}"
VMS="${VMS:-vm-nat vm-lb vm-fw}"
ECHO_URL="${ECHO_URL:-https://api.ipify.org}" # any plain-text 'what is my IP' endpoint will do

run_on() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv
}

case "${1:-}" in
  ip)
    for vm in $VMS; do
      echo "== $vm sees itself as:"
      run_on "$vm" "curl -s -m 8 $ECHO_URL || echo TIMEOUT"
    done
    ;;
  routes)
    for vm in $VMS; do
      echo "== effective routes of $vm-nic"
      az network nic show-effective-route-table -g "$RG" -n "$vm-nic" \
        --query "value[].{prefix:addressPrefix[0], nextHopType:nextHopType, nextHop:nextHopIpAddress[0], source:source}" -o table
    done
    ;;
  attach)
    for s in snet-nat snet-lb snet-fw; do
      echo "== $s"
      az network vnet subnet show -g "$RG" --vnet-name "${PREFIX:-snat22}-vnet" -n "$s" \
        --query "{natGateway:natGateway.id, routeTable:routeTable.id, defaultOutboundAccess:defaultOutboundAccess}" -o json
    done
    ;;
  metrics)
    LB_ID=$(az network lb show -g "$RG" -n "${PREFIX:-snat22}-lb" --query id -o tsv)
    az monitor metrics list --resource "$LB_ID" --metric SnatConnectionCount AllocatedSnatPorts UsedSnatPorts \
      --aggregation Total Average --interval PT1M --offset 30m -o table
    ;;
  *)
    echo "usage: $0 ip | routes | attach | metrics" >&2
    exit 2
    ;;
esac
