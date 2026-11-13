#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities: lists the resolver objects and runs dig on the lab VMs.
# Needs: az CLI signed in with the dns-resolver extension, the lab applied, VMs running (check current docs for the extension name).
# Usage: ./scripts/verify.sh objects | queries | zone
set -euo pipefail

RG="${RG:-dns21-rg}"
RESOLVER="${RESOLVER:-dns21-resolver}"
RULESET="${RULESET:-dns21-ruleset}"
SA_FQDN="${SA_FQDN:-}"   # set to the storage_account_fqdn output for the private endpoint checks

ask() { # vm command
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" --query "value[0].message" -o tsv
}

case "${1:-}" in
  objects)
    az dns-resolver inbound-endpoint list -g "$RG" --dns-resolver-name "$RESOLVER" -o table
    az dns-resolver outbound-endpoint list -g "$RG" --dns-resolver-name "$RESOLVER" -o table
    az dns-resolver forwarding-rule list -g "$RG" --ruleset-name "$RULESET" -o table
    az dns-resolver vnet-link list -g "$RG" --ruleset-name "$RULESET" -o table
    ;;
  queries)
    echo "== 1 spoke-vm: corp name through the ruleset (expect 10.60.1.30)"
    ask spoke-vm "dig +short +time=3 +tries=1 files.corp.example.com"
    echo "== 2 onprem-client: corp name locally (expect 10.60.1.30)"
    ask onprem-client "dig +short +time=3 +tries=1 files.corp.example.com"
    echo "== 3 onprem-client: storage name (expect a 10.50.2.x address when the forwarder is right)"
    ask onprem-client "dig +short +time=3 +tries=1 ${SA_FQDN}"
    echo "== 4 spoke-vm: storage name (depends on the spoke DNS setting)"
    ask spoke-vm "dig +short +time=3 +tries=1 ${SA_FQDN}"
    ;;
  zone)
    az network private-dns record-set a list -g "$RG" -z privatelink.blob.core.windows.net -o table
    ;;
  *)
    echo "usage: $0 objects | queries | zone" >&2
    exit 2
    ;;
esac
