#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities. It never changes anything in Azure.
# Needs: az CLI signed in. Most modes need the matching gate applied and, for circuit modes, a real circuit.
# Usage: ./scripts/er-check.sh gateway | effective | metrics-defs | cpu | pps | circuit | direct | connection | arp | summary | globalreach
set -euo pipefail

RG="${RG:-er34-rg}"
GW="${GW:-er34-ergw}"
CIRCUIT="${CIRCUIT:-er34-circuit}"
PORT="${PORT:-er34-port}"
CONN="${CONN:-er34-er-conn}"
NIC="${NIC:-vm-app-nic}"
PEERING="${PEERING:-AzurePrivatePeering}"

gw_id() { az network vnet-gateway show -g "$RG" -n "$GW" --query id -o tsv; }

case "${1:-}" in
  gateway)
    az network vnet-gateway show -g "$RG" -n "$GW" \
      --query "{sku:sku.name, type:gatewayType, state:provisioningState}" -o table
    ;;
  effective)
    az network nic show-effective-route-table -g "$RG" -n "$NIC" -o table
    ;;
  metrics-defs)
    az monitor metrics list-definitions --resource "$(gw_id)" --query "[].name.value" -o tsv
    ;;
  cpu)
    az monitor metrics list --resource "$(gw_id)" --metric ExpressRouteGatewayCpuUtilization \
      --interval PT5M --aggregation Average Maximum -o table
    ;;
  pps)
    az monitor metrics list --resource "$(gw_id)" --metric ExpressRouteGatewayPacketsPerSecond \
      --interval PT5M --aggregation Average Maximum -o table
    ;;
  circuit)
    az network express-route show -g "$RG" -n "$CIRCUIT" \
      --query "{circuit:circuitProvisioningState, provider:serviceProviderProvisioningState, mbps:serviceProviderProperties.bandwidthInMbps, tier:sku.tier, family:sku.family, key:serviceKey}" -o table
    ;;
  direct)
    az network express-route port show -g "$RG" -n "$PORT" \
      --query "{gbps:provisionedBandwidthInGbps, encapsulation:encapsulation, location:peeringLocation, links:links[].{name:name, admin:adminState}}" -o json
    ;;
  connection)
    az network vpn-connection show -g "$RG" -n "$CONN" \
      --query "{status:connectionStatus, fastpath:expressRouteGatewayBypass, type:connectionType}" -o table
    ;;
  arp)
    for path in primary secondary; do
      echo "== ARP, $path"
      az network express-route list-arp-tables -g "$RG" -n "$CIRCUIT" --path "$path" --peering-name "$PEERING" -o table
    done
    ;;
  summary)
    for path in primary secondary; do
      echo "== Route table summary, $path"
      az network express-route list-route-tables-summary -g "$RG" -n "$CIRCUIT" --path "$path" --peering-name "$PEERING" -o table
    done
    ;;
  globalreach)
    az network express-route show -g "$RG" -n "$CIRCUIT" \
      --query "peerings[].{peering:name, connections:connections[].{name:name, state:circuitConnectionStatus, range:addressPrefix}}" -o json
    ;;
  *)
    echo "usage: $0 gateway|effective|metrics-defs|cpu|pps|circuit|direct|connection|arp|summary|globalreach" >&2
    exit 2
    ;;
esac
