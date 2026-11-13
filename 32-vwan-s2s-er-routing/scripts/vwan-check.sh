#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities: it never changes anything in Azure.
# Needs: az CLI signed in and the lab applied. The az vhub sub-commands and their flags change between versions: check current docs.
# Usage: ./scripts/vwan-check.sh tables | routes <table> | conn <connection> | nic <vm> | ping <from-vm> <to-ip> | device
set -euo pipefail

RG="${RG:-vwan32-rg}"
HUB="${HUB:-vwan32-hub1}"

run_on() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv
}

case "${1:-}" in
  tables)
    az network vhub route-table list -g "$RG" --vhub-name "$HUB" \
      --query "[].{name:name, labels:labels, routes:length(routes)}" -o table
    ;;
  routes)
    # effective routes of a hub route table: ./vwan-check.sh routes defaultRouteTable
    T="${2:?usage: vwan-check.sh routes <route-table-name>}"
    ID=$(az network vhub show -g "$RG" -n "$HUB" --query id -o tsv)
    az network vhub get-effective-routes -g "$RG" -n "$HUB" \
      --resource-type RouteTable --resource-id "$ID/hubRouteTables/$T" -o table
    ;;
  conn)
    # effective routes of a connection (what the connection learns): ./vwan-check.sh conn conn-prod
    C="${2:?usage: vwan-check.sh conn <connection-name>}"
    ID=$(az network vhub connection show -g "$RG" --vhub-name "$HUB" -n "$C" --query id -o tsv)
    az network vhub get-effective-routes -g "$RG" -n "$HUB" \
      --resource-type VirtualNetworkConnection --resource-id "$ID" -o table
    ;;
  nic)
    V="${2:?usage: vwan-check.sh nic <vm-short-name e.g. prod>}"
    az network nic show-effective-route-table -g "$RG" -n "vm-$V-nic" \
      --query "value[].{prefix:addressPrefix[0], nextHopType:nextHopType, nextHop:nextHopIpAddress[0], source:source}" -o table
    ;;
  ping)
    run_on "${2:?from vm}" "ping -c 3 -W 2 ${3:?to ip}"
    ;;
  device)
    run_on vm-edge "swanctl --list-sas | head -30; vtysh -c 'show ip bgp summary'; vtysh -c 'show ip bgp'"
    ;;
  *)
    echo "usage: $0 tables | routes <table> | conn <connection> | nic <vm> | ping <from-vm> <to-ip> | device" >&2
    exit 2
    ;;
esac
