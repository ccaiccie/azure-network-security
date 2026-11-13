#!/usr/bin/env bash
# Read-only helper for the Bastion and JIT lab. Designed, not tested. It only reads settings with az CLI;
# it creates, changes and deletes nothing and it never sends traffic to anything.
# Usage: ./scripts/bastion-check.sh subnet|nsg|vm|peering|bastion|jit|all
set -euo pipefail
RG="${RG:-bas33-rg}"
HUB="${HUB:-bas33-vnet-hub}"
NSG="${NSG:-bas33-nsg-bastion}"
APPNSG="${APPNSG:-bas33-nsg-app}"
NIC="${NIC:-bas33-nic-app}"
BAS="${BAS:-bas33-bastion}"

subnet() {
  echo "== AzureBastionSubnet: exact name, /26 or larger, NSG attached =="
  az network vnet subnet show -g "$RG" --vnet-name "$HUB" -n AzureBastionSubnet \
    --query "{name:name, prefix:addressPrefix, nsg:networkSecurityGroup.id, routeTable:routeTable.id}" -o json
}
nsg() {
  echo "== NSG on AzureBastionSubnet: GatewayManager 443 must be present =="
  az network nsg rule list -g "$RG" --nsg-name "$NSG" \
    --query "[].{n:name, dir:direction, pri:priority, src:sourceAddressPrefix, port:destinationPortRange, ports:destinationPortRanges, dst:destinationAddressPrefix}" -o table
}
vm() {
  echo "== vm-app NIC: private IP, and no public IP unless vm_public_ip is true =="
  az network nic show -g "$RG" -n "$NIC" \
    --query "{private:ipConfigurations[0].privateIPAddress, public:ipConfigurations[0].publicIPAddress.id}" -o json
  echo "== Effective security rules (both NSGs are merged here) =="
  az network nic list-effective-nsg -g "$RG" -n "$NIC" -o json 2>/dev/null | head -n 40 || echo "VM not running or no NIC"
}
peering() {
  echo "== Hub peerings: state must be Connected =="
  az network vnet peering list -g "$RG" --vnet-name "$HUB" \
    --query "[].{name:name, state:peeringState, access:allowVirtualNetworkAccess}" -o table
}
bastion() {
  echo "== Bastion: SKU, state and features =="
  az network bastion show -g "$RG" -n "$BAS" \
    --query "{sku:sku.name, state:provisioningState, tunneling:enableTunneling, ipConnect:enableIpConnect, shareable:enableShareableLink}" -o json 2>/dev/null || echo "no Bastion named $BAS"
}
jit() {
  echo "== App NSG: look for JIT deny and allow rules =="
  az network nsg rule list -g "$RG" --nsg-name "$APPNSG" \
    --query "[].{n:name, pri:priority, access:access, src:sourceAddressPrefix, port:destinationPortRange}" -o table
  echo "== JIT policies in the subscription (check current az CLI) =="
  az security jit-policy list -o table 2>/dev/null || echo "no JIT policy listing available"
}
case "${1:-all}" in
  subnet) subnet ;;
  nsg) nsg ;;
  vm) vm ;;
  peering) peering ;;
  bastion) bastion ;;
  jit) jit ;;
  all) subnet; nsg; vm; peering; bastion; jit ;;
  *) echo "usage: $0 subnet|nsg|vm|peering|bastion|jit|all" >&2; exit 2 ;;
esac
