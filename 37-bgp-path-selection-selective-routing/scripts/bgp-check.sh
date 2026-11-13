#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities. It never changes anything in Azure.
# Needs: az CLI signed in and the lab applied (gate 1 and, for most modes, gate 2).
# Usage: ./scripts/bgp-check.sh rs-peers | rs-learned <nva-a|nva-b> | rs-advertised <nva-a|nva-b> | app-routes | nva <nva-a|nva-b> | gw-learned | gw-advertised <peer-ip> | gw-peers
set -euo pipefail

RG="${RG:-bgp37-rg}"
RS="${RS:-bgp37-rs}"
GW="${GW:-bgp37-vpngw}"
APP_NIC="${APP_NIC:-vm-app-nic}"

run_on() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv
}

case "${1:-}" in
  rs-peers)
    az network routeserver peering list -g "$RG" --routeserver "$RS" -o table
    ;;
  rs-learned)
    az network routeserver peering list-learned-routes -g "$RG" --routeserver "$RS" -n "${2:?peer name}" -o table
    ;;
  rs-advertised)
    az network routeserver peering list-advertised-routes -g "$RG" --routeserver "$RS" -n "${2:?peer name}" -o table
    ;;
  app-routes)
    az network nic show-effective-route-table -g "$RG" -n "$APP_NIC" \
      --query "value[].{prefix:addressPrefix[0], nextHopType:nextHopType, nextHop:nextHopIpAddress[0], source:source, state:state}" -o table
    ;;
  nva)
    run_on "${2:?vm name}" "vtysh -c 'show ip bgp summary'; vtysh -c 'show ip bgp'"
    ;;
  gw-peers)
    az network vnet-gateway list-bgp-peer-status -g "$RG" -n "$GW" -o table
    ;;
  gw-learned)
    az network vnet-gateway list-learned-routes -g "$RG" -n "$GW" -o table
    ;;
  gw-advertised)
    az network vnet-gateway list-advertised-routes -g "$RG" -n "$GW" --peer "${2:?peer ip}" -o table
    ;;
  *)
    echo "usage: $0 rs-peers|rs-learned <peer>|rs-advertised <peer>|app-routes|nva <vm>|gw-peers|gw-learned|gw-advertised <peer-ip>"; exit 1 ;;
esac
