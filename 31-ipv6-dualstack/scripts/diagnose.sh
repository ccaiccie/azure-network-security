#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities. It only reads Azure state and runs commands on the lab VMs
# through the Azure agent (run-command needs no network path to the VMs).
# Needs: az CLI signed in. The VM modes need gate 1 and running VMs.
# Usage: ./scripts/diagnose.sh vnet | nsg | routes VM | nic VM | lb | dns | peer | v6 VM | get VM FAMILY URL | resolve VM NAME
set -euo pipefail

RG="${RG:-ds31-rg}"
PREFIX="${PREFIX:-ds31}"

runon() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "$2" --query 'value[0].message' -o tsv
}

case "${1:-}" in
  vnet)
    echo "== address space and subnet prefixes (expect one IPv4 and one IPv6 each)"
    az network vnet show -g "$RG" -n "${PREFIX}-vnet" --query '{space:addressSpace.addressPrefixes, subnets:subnets[].{name:name, prefixes:addressPrefixes}}' -o json
    ;;
  nsg)
    echo "== NSG rules (look for a rule whose source is ::/0)"
    az network nsg rule list -g "$RG" --nsg-name "${PREFIX}-nsg-app" \
      --query '[].{name:name, priority:priority, access:access, port:destinationPortRange, source:sourceAddressPrefix}' -o table
    ;;
  nic)
    VM="${2:?usage: $0 nic VM}"
    echo "== IP configurations of $VM (expect ipconfig1 IPv4 and ipconfig2 IPv6)"
    az network nic show -g "$RG" -n "${VM}-nic" \
      --query 'ipConfigurations[].{name:name, version:privateIPAddressVersion, address:privateIPAddress, primary:primary, publicIp:publicIPAddress.id}' -o json
    ;;
  routes)
    VM="${2:?usage: $0 routes VM}"
    echo "== effective routes of $VM (compare the IPv4 rows with the IPv6 rows)"
    az network nic show-effective-route-table -g "$RG" -n "${VM}-nic" -o table
    ;;
  lb)
    echo "== load balancer frontends, pools and rules"
    az network lb show -g "$RG" -n "${PREFIX}-lb" \
      --query '{frontends:frontendIPConfigurations[].name, pools:backendAddressPools[].name, rules:loadBalancingRules[].{name:name, frontend:frontendIPConfiguration.id}}' -o json
    az network public-ip list -g "$RG" --query '[].{name:name, version:publicIPAddressVersion, address:ipAddress, sku:sku.name}' -o table
    ;;
  dns)
    echo "== records in the private zone ds31.internal"
    az network private-dns record-set list -g "$RG" -z ds31.internal \
      --query '[].{name:name, type:type, a:aRecords[].ipv4Address, aaaa:aaaaRecords[].ipv6Address}' -o json
    ;;
  peer)
    echo "== peering state"
    az network vnet peering list -g "$RG" --vnet-name "${PREFIX}-vnet" \
      --query '[].{name:name, state:peeringState, remote:remoteAddressSpace.addressPrefixes}' -o json
    ;;
  v6)
    VM="${2:?usage: $0 v6 VM}"
    echo "== $VM addresses and routes seen inside the guest"
    runon "$VM" "ip -6 addr show scope global; ip -6 route"
    ;;
  get)
    VM="${2:?usage: $0 get VM FAMILY URL}"; FAM="${3:?FAMILY is 4 or 6}"; URL="${4:?usage: $0 get VM FAMILY URL}"
    echo "== $VM requests $URL over IPv$FAM"
    runon "$VM" "curl -$FAM -s -m 8 -o /dev/null -w 'HTTP %{http_code}\n' '$URL' || echo curl-failed"
    ;;
  resolve)
    VM="${2:?usage: $0 resolve VM NAME}"; NAME="${3:?usage: $0 resolve VM NAME}"
    echo "== $VM resolves $NAME (IPv4, then IPv6, then the order a client would try)"
    runon "$VM" "getent ahostsv4 '$NAME' | head -1 || echo no-A; getent ahostsv6 '$NAME' | head -1 || echo no-AAAA"
    ;;
  *)
    echo "usage: $0 vnet | nsg | routes VM | nic VM | lb | dns | peer | v6 VM | get VM FAMILY URL | resolve VM NAME" >&2
    exit 2
    ;;
esac
