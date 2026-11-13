#!/usr/bin/env bash
# Prints the four facts that explain almost every peering problem. Designed, not tested.
# Usage: ./scripts/diagnose.sh <resource-group> <vnet-name> <nic-name>
set -euo pipefail
rg="${1:?resource group}"; vnet="${2:?vnet name}"; nic="${3:-}"

echo "== peering links on ${vnet}: state, sync, and the four properties"
az network vnet peering list -g "$rg" --vnet-name "$vnet" \
  --query "[].{name:name, state:peeringState, sync:peeringSyncLevel, access:allowVirtualNetworkAccess, fwd:allowForwardedTraffic, gwt:allowGatewayTransit, rgw:useRemoteGateways, remote:remoteAddressSpace.addressPrefixes}" -o table

if [ -n "$nic" ]; then
  echo "== effective routes on ${nic}"
  az network nic show-effective-route-table -g "$rg" -n "$nic" -o table
fi
