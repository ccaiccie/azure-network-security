#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities. It only reads Azure state and runs curl on the lab VMs
# through the Azure agent (no network path is needed to the VMs).
# Needs: az CLI signed in. The get/body modes need gate 1 and running VMs.
# Usage: ./scripts/diagnose.sh acct | subnets | routes VM | conns | pls | get VM URL | body VM URL | resolve VM NAME
set -euo pipefail

RG="${RG:-pl27-rg}"
OTHER_RG="${OTHER_RG:-pl27-other-rg}"
PREFIX="${PREFIX:-pl27}"

runon() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "$2" --query 'value[0].message' -o tsv
}

acct_name() { az storage account list -g "$RG" --query '[0].name' -o tsv; }

case "${1:-}" in
  acct)
    A="${ACCT:-$(acct_name)}"
    echo "== network settings of $A"
    az storage account show -g "$RG" -n "$A" \
      --query '{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction, bypass:networkRuleSet.bypass, vnetRules:networkRuleSet.virtualNetworkRules[].virtualNetworkResourceId, ipRules:networkRuleSet.ipRules[].value}' -o json
    ;;
  subnets)
    for s in snet-se snet-pe snet-plain; do
      echo "== $s"
      az network vnet subnet show -g "$RG" --vnet-name "${PREFIX}-vnet-con" -n "$s" \
        --query '{serviceEndpoints:serviceEndpoints[].service, policies:serviceEndpointPolicies[].id, peNetworkPolicies:privateEndpointNetworkPolicies}' -o json
    done
    ;;
  routes)
    VM="${2:?usage: $0 routes VM}"
    echo "== effective routes of $VM (look for the next hop types)"
    az network nic show-effective-route-table -g "$RG" -n "${VM}-nic" -o table
    ;;
  conns)
    A="${ACCT:-$(acct_name)}"
    ID="$(az storage account show -g "$RG" -n "$A" --query id -o tsv)"
    echo "== private endpoint connections of $A"
    az network private-endpoint-connection list --id "$ID" \
      --query '[].{name:name, state:properties.privateLinkServiceConnectionState.status, message:properties.privateLinkServiceConnectionState.description}' -o table
    ;;
  pls)
    echo "== Private Link Service"
    az network private-link-service show -g "$RG" -n "${PREFIX}-pls" \
      --query '{alias:alias, proxyProtocol:enableProxyProtocol, natIps:ipConfigurations[].privateIPAddress, visibility:visibility.subscriptions, autoApproval:autoApproval.subscriptions, connections:privateEndpointConnections[].privateLinkServiceConnectionState.status}' -o json
    ;;
  get)
    VM="${2:?usage: $0 get VM URL}"; URL="${3:?usage: $0 get VM URL}"
    echo "== $VM requests $URL"
    runon "$VM" "curl -s -m 10 -o /dev/null -w 'HTTP %{http_code}\n' '$URL' || echo curl-failed"
    ;;
  body)
    VM="${2:?usage: $0 body VM URL}"; URL="${3:?usage: $0 body VM URL}"
    echo "== $VM requests $URL"
    runon "$VM" "curl -s -m 10 '$URL' || echo curl-failed"
    ;;
  resolve)
    VM="${2:?usage: $0 resolve VM NAME}"; NAME="${3:?usage: $0 resolve VM NAME}"
    echo "== $VM resolves $NAME"
    runon "$VM" "getent hosts '$NAME' || echo no-answer"
    ;;
  *)
    echo "usage: $0 acct | subnets | routes VM | conns | pls | get VM URL | body VM URL | resolve VM NAME" >&2
    exit 2
    ;;
esac
