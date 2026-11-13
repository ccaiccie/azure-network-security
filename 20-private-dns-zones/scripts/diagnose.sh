#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities: lists links and records, shows the VNet DNS servers,
# and runs the DNS client on the lab VMs through the Azure agent (no network path is needed).
# Needs: az CLI signed in. The query mode needs gate 1 and a running VM.
# Usage: ./scripts/diagnose.sh links | records | vnetdns | query NAME [SERVER]
set -euo pipefail

RG="${RG:-dns20-rg}"
ZONE="${ZONE:-lab20.example}"
PL_ZONE="privatelink.blob.core.windows.net"

ask() { # vm name server
  echo "== $1 asks ${3:-168.63.129.16} for $2"
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "python3 /opt/lab/dnsq.py $2 ${3:-168.63.129.16}" --query 'value[0].message' -o tsv
}

case "${1:-}" in
  links)
    for z in "$ZONE" "$PL_ZONE"; do
      echo "== links of $z"
      az network private-dns link vnet list -g "$RG" -z "$z" -o table 2>/dev/null || echo "(zone not created)"
    done
    ;;
  records)
    for z in "$ZONE" "$PL_ZONE"; do
      echo "== records of $z"
      az network private-dns record-set list -g "$RG" -z "$z" -o table 2>/dev/null || echo "(zone not created)"
    done
    ;;
  vnetdns)
    for v in dns20-vnet-app dns20-vnet-spoke; do
      echo "== DNS servers of $v (empty means Azure-provided DNS)"
      az network vnet show -g "$RG" -n "$v" --query 'dhcpOptions.dnsServers' -o json
    done
    ;;
  query)
    NAME="${2:?usage: $0 query NAME [SERVER]}"
    ask vm-app-1 "$NAME" "${3:-}"
    ask vm-spoke-1 "$NAME" "${3:-}"
    ;;
  *)
    echo "usage: $0 links | records | vnetdns | query NAME [SERVER]" >&2
    exit 2
    ;;
esac
