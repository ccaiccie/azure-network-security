#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities. It never changes anything in Azure.
# Needs: az CLI signed in, the lab applied (gate 1, and gates 2 and 3 for most modes).
# Usage: ./scripts/vpn-check.sh status | bgp | learned | advertised | routes | metrics | device
set -euo pipefail

RG="${RG:-vpn26-rg}"
GW="${GW:-vpn26-vpngw}"
CONN="${CONN:-vpn26-conn-onprem}"
APP_NIC="${APP_NIC:-vm-app-nic}"

run_on() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv
}

case "${1:-}" in
  status)
    az network vpn-connection show -g "$RG" -n "$CONN" \
      --query "{status:connectionStatus, protocol:connectionProtocol, bgp:enableBgp, in:ingressBytesTransferred, out:egressBytesTransferred}" -o table
    ;;
  bgp)
    az network vnet-gateway list-bgp-peer-status -g "$RG" -n "$GW" -o table
    ;;
  learned)
    az network vnet-gateway list-learned-routes -g "$RG" -n "$GW" -o table
    ;;
  advertised)
    PEER="${2:?usage: vpn-check.sh advertised <peer-ip>}"
    az network vnet-gateway list-advertised-routes -g "$RG" -n "$GW" --peer "$PEER" -o table
    ;;
  routes)
    az network nic show-effective-route-table -g "$RG" -n "$APP_NIC" \
      --query "value[].{prefix:addressPrefix[0], nextHopType:nextHopType, nextHop:nextHopIpAddress[0], source:source, state:state}" -o table
    ;;
  metrics)
    ID=$(az network vpn-connection show -g "$RG" -n "$CONN" --query id -o tsv)
    az monitor metrics list --resource "$ID" \
      --metric TunnelIngressBytes TunnelEgressBytes TunnelIngressPacketDropTSMismatch TunnelEgressPacketDropTSMismatch \
      --interval PT5M --offset 1h --aggregation Total -o table
    ;;
  device)
    echo "== IPsec security associations on vm-edge"
    run_on vm-edge "swanctl --list-sas | head -40"
    echo "== BGP summary on vm-edge"
    run_on vm-edge "vtysh -c 'show ip bgp summary' 2>&1 | head -20"
    ;;
  *)
    echo "usage: $0 status|bgp|learned|advertised <peer>|routes|metrics|device"; exit 1 ;;
esac
