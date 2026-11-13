#!/usr/bin/env bash
# Read-only: prints what the load balancer is configured to do and what it thinks of its backends. Designed, not tested.
# Usage: ./scripts/lb-diagnose.sh <resource-group> [lb-name]
set -euo pipefail
rg="${1:?resource group}"; lb="${2:-lb-internal}"

echo "== rules: protocol, ports, distribution, floating IP, idle timeout"
az network lb rule list -g "$rg" --lb-name "$lb" \
  --query "[].{name:name, proto:protocol, fe:frontendPort, be:backendPort, dist:loadDistribution, float:enableFloatingIp, idle:idleTimeoutInMinutes}" -o table

echo "== probes: protocol, port, path, interval, count"
az network lb probe list -g "$rg" --lb-name "$lb" \
  --query "[].{name:name, proto:protocol, port:port, path:requestPath, interval:intervalInSeconds, count:numberOfProbes}" -o table

echo "== backend pool members"
az network lb address-pool list -g "$rg" --lb-name "$lb" \
  --query "[].{pool:name, nics:backendIpConfigurations[].id}" -o json

echo "== data path availability and health probe status, last 15 minutes, 1-minute average"
id=$(az network lb show -g "$rg" -n "$lb" --query id -o tsv)
az monitor metrics list --resource "$id" --metric VipAvailability DipAvailability \
  --interval PT1M --aggregation Average --offset 15m -o table
