#!/usr/bin/env bash
# Sourced operator-only helpers. No cloud mutation and no secret retrieval.
set -euo pipefail
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
load_context() {
  : "${SUBSCRIPTION_ID:?Set approved subscription UUID explicitly}"
  [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { printf 'Invalid approved subscription UUID.\n' >&2; exit 2; }
  for tool in terraform az python3; do command -v "$tool" >/dev/null || exit 2; done
  TF_OUTPUTS=$(terraform -chdir="$ROOT" output -json)
  read_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1"; }
  [[ "$(read_output deployment_enabled)" == True ]] || { printf 'Lab deployment is disabled or state missing.\n' >&2; exit 2; }
  RS_ID=$(read_output route_server_id)
  [[ "$RS_ID" =~ ^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Network/virtualHubs/[^/]+$ ]] || { printf 'Invalid Route Server resource ID in state.\n' >&2; exit 2; }
  SUBSCRIPTION_ID=$(printf '%s' "$SUBSCRIPTION_ID" | tr '[:upper:]' '[:lower:]')
  STATE_SUB=$(printf '%s' "$RS_ID" | cut -d/ -f3 | tr '[:upper:]' '[:lower:]')
  [[ "$STATE_SUB" == "$SUBSCRIPTION_ID" ]] || { printf 'Approved subscription does not match lab state.\n' >&2; exit 2; }
  RG=$(read_output resource_group_name)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
