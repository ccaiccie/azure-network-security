#!/usr/bin/env bash
# Offline source checks for the routes lab. Designed, not tested against a real checkout.
# Whitespace-tolerant on purpose, so `terraform fmt` realignment never breaks it.
set -eu
cd "$(dirname "$0")/.."
fail=0
check() { if ! grep -Eq "$2" "$1"; then echo "MISSING in $1: $2"; fail=1; fi; }
for gate in deploy_lab enable_udr_forward enable_return_route enable_blackhole_route enable_default_route enable_service_tag_route; do
  check variables.tf "variable[[:space:]]+\"$gate\""
done
# every gate defaults to false
awk '/^variable "(deploy_lab|enable_[a-z_]+)"/{g=1} g&&/^[[:space:]]*default[[:space:]]*=/{ if ($0 !~ /false/) {print "gate default is not false: " $0; bad=1} g=0 } END{exit bad}' variables.tf || fail=1
check routes.tf 'address_prefix[[:space:]]*=[[:space:]]*"10\.20\.0\.0/16"'
check routes.tf 'address_prefix[[:space:]]*=[[:space:]]*"10\.10\.1\.0/24"'
check routes.tf 'bgp_route_propagation_enabled'
check compute.tf 'ip_forwarding_enabled'
if grep -Eq 'azurerm_subnet_route_table_association"[[:space:]]+"nva"' routes.tf; then echo "snet-nva must not get a route table"; fail=1; fi
[ "$fail" -eq 0 ] && echo "source checks passed"
exit "$fail"
