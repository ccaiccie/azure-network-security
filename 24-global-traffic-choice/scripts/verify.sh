#!/usr/bin/env bash
# Designed, not tested. Read-only helper for the activities: asks each entry point what the backend sees.
# Needs: curl, dig, and the outputs of the applied lab (terraform output -raw ...). Changes nothing in Azure.
# Usage: ./scripts/verify.sh lb | appgw | afd | tm | health
set -euo pipefail

RG="${RG:-gtc24-rg}"
LB_FQDN="${LB_FQDN:-}"
APPGW_FQDN="${APPGW_FQDN:-}"
AFD_HOST="${AFD_HOST:-}"
TM_FQDN="${TM_FQDN:-}"
AGW_NAME="${AGW_NAME:-gtc24-agw}"

show() { # name url
  echo "== $1 ($2)"
  curl -sS --max-time 10 -i "$2" | sed -n '1p;/^[Xx]-/p;/^host=/,$p'
}

case "${1:-}" in
  lb)    show "load balancer: client address is kept" "http://${LB_FQDN}/" ;;
  appgw) show "application gateway: backend sees the gateway, XFF has the client" "http://${APPGW_FQDN}/" ;;
  afd)   show "front door: X-Azure-ClientIP and XFF" "http://${AFD_HOST}/" ;;
  tm)
    echo "== dig the Traffic Manager name (answer and TTL)"
    dig +noall +answer "${TM_FQDN}"
    show "the endpoint Traffic Manager returned" "http://${TM_FQDN}/"
    ;;
  health)
    az network application-gateway show-backend-health -g "$RG" -n "$AGW_NAME" \
      --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].{address:address, health:health}" -o table
    ;;
  *) echo "usage: $0 lb | appgw | afd | tm | health" >&2; exit 2 ;;
esac
