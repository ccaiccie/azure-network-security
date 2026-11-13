#!/usr/bin/env bash
# Read-only helper for the Firewall Manager and IP groups lab. Designed, not tested. It only reads settings with az CLI;
# it creates, changes and deletes nothing and it never sends traffic to anything.
# The `az network firewall` commands need the azure-firewall extension (check current docs).
# Usage: ./scripts/policy-check.sh parent|children|groups|ipgroups|settings|firewall|audit|all
set -euo pipefail
RG="${RG:-fm35-rg}"
PARENT="${PARENT:-fm35-fp-parent}"
CHILD_A="${CHILD_A:-fm35-fp-child-a}"
CHILD_B="${CHILD_B:-fm35-fp-child-b}"
FW="${FW:-fm35-fw}"

parent() {
  echo "== Parent policy: tier, and which child policies and firewalls use it =="
  az network firewall policy show -g "$RG" -n "$PARENT" \
    --query "{name:name, tier:sku.tier, children:childPolicies[].id, firewalls:firewalls[].id}" -o json
}
children() {
  echo "== Child policies: the base policy each one inherits from =="
  for p in "$CHILD_A" "$CHILD_B"; do
    az network firewall policy show -g "$RG" -n "$p" \
      --query "{name:name, base:basePolicy.id, firewalls:firewalls[].id}" -o json
  done
}
groups() {
  echo "== Rule collection groups: name and priority, parent then children =="
  for p in "$PARENT" "$CHILD_A" "$CHILD_B"; do
    echo "-- $p"
    az network firewall policy rule-collection-group list -g "$RG" --policy-name "$p" \
      --query "[].{group:name, priority:priority}" -o table
  done
}
ipgroups() {
  echo "== IP groups: prefixes, and which firewalls and policies use each =="
  az network ip-group list -g "$RG" \
    --query "[].{name:name, cidrs:ipAddresses, firewalls:firewalls[].id, policies:firewallPolicies[].id}" -o json
}
settings() {
  echo "== Settings: DNS proxy, threat intelligence and IDPS per policy =="
  for p in "$PARENT" "$CHILD_A" "$CHILD_B"; do
    az network firewall policy show -g "$RG" -n "$p" \
      --query "{name:name, dns:dnsSettings, threatIntel:threatIntelMode, idps:intrusionDetection.mode}" -o json
  done
}
firewall() {
  echo "== Firewall: which policy it uses (empty means NOT associated) =="
  az network firewall show -g "$RG" -n "$FW" \
    --query "{name:name, tier:sku.tier, policy:firewallPolicy.id, state:provisioningState}" -o json
}
audit() {
  echo "== Azure Policy compliance for the lab resource group (gate 3) =="
  az policy state list -g "$RG" --query "[].{resource:resourceId, state:complianceState}" -o table
}
case "${1:-all}" in
  parent) parent ;;
  children) children ;;
  groups) groups ;;
  ipgroups) ipgroups ;;
  settings) settings ;;
  firewall) firewall ;;
  audit) audit ;;
  all) parent; children; groups; ipgroups; settings ;;
  *) echo "usage: $0 parent|children|groups|ipgroups|settings|firewall|audit|all"; exit 2 ;;
esac
