#!/usr/bin/env bash
# Sourced operator-only helpers. No cloud mutation and no secret retrieval.
set -euo pipefail
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
load_context() {
  : "${SUBSCRIPTION_ID:?Set approved subscription UUID explicitly}"
  for tool in terraform az python3; do command -v "$tool" >/dev/null || exit 2; done
  TF_OUTPUTS=$(terraform -chdir="$ROOT" output -json)
  read_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1"; }
  [[ "$(read_output deployment_enabled)" == True ]] || { printf 'Lab deployment is disabled or state missing.\n' >&2; exit 2; }
  FW_ID=$(read_output firewall_id)
  SUBSCRIPTION_ID=$(printf '%s' "$SUBSCRIPTION_ID" | tr '[:upper:]' '[:lower:]')
  STATE_SUB=$(printf '%s' "$FW_ID" | cut -d/ -f3 | tr '[:upper:]' '[:lower:]')
  [[ "$STATE_SUB" == "$SUBSCRIPTION_ID" ]] || { printf 'Approved subscription does not match lab state.\n' >&2; exit 2; }
  RG=$(read_output resource_group_name)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
