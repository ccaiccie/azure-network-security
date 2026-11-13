#!/usr/bin/env bash
# Designed, not tested. Read-mostly helper for the activities: Network Watcher tools, flow log settings and a curl between the VMs.
# It changes nothing in Azure except `capture`, which starts and stops one short packet capture.
# Needs: az CLI signed in, and the lab applied with deploy_vms = true. Flow log and workspace modes need gates 2 and 3.
# Usage: ./scripts/netwatch-check.sh topology | routes | rules | nexthop | ipflow | connect | flowlogs | capture | query | app
set -euo pipefail

P="${PREFIX:-nw28}"
RG="${RG:-$P-rg}"
LOC="${LOCATION:-westeurope}"
PORT="${APP_PORT:-8080}"
CLIENT_IP="10.80.0.10"
SERVER_IP="10.81.0.10"

run_on() { # vm script
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv
}

case "${1:-}" in
  topology)
    az network watcher show-topology -g "$RG" -o json
    ;;
  routes)
    echo "== effective routes of vm-client-nic"
    az network nic show-effective-route-table -g "$RG" -n vm-client-nic \
      --query "value[].{prefix:addressPrefix[0], nextHopType:nextHopType, nextHop:nextHopIpAddress[0], source:source, state:state}" -o table
    echo "== effective routes of vm-server-nic"
    az network nic show-effective-route-table -g "$RG" -n vm-server-nic \
      --query "value[].{prefix:addressPrefix[0], nextHopType:nextHopType, nextHop:nextHopIpAddress[0], source:source, state:state}" -o table
    ;;
  rules)
    echo "== effective security rules of vm-server-nic"
    az network nic list-effective-nsg -g "$RG" -n vm-server-nic -o json
    ;;
  nexthop)
    echo "== next hop from vm-client to the server IP"
    az network watcher show-next-hop -g "$RG" --vm vm-client --source-ip "$CLIENT_IP" --dest-ip "$SERVER_IP" -o json
    ;;
  ipflow)
    echo "== IP flow verify: inbound TCP $PORT to vm-server"
    az network watcher test-ip-flow -g "$RG" --vm vm-server --direction Inbound --protocol TCP \
      --local "$SERVER_IP:$PORT" --remote "$CLIENT_IP:50000" -o json
    echo "== IP flow verify: the same port from an address outside the VNets (documentation range)"
    az network watcher test-ip-flow -g "$RG" --vm vm-server --direction Inbound --protocol TCP \
      --local "$SERVER_IP:$PORT" --remote "198.51.100.7:50000" -o json
    ;;
  connect)
    echo "== connection check vm-client to $SERVER_IP:$PORT"
    az network watcher test-connectivity -g "$RG" --source-resource vm-client --dest-address "$SERVER_IP" --dest-port "$PORT" -o json
    ;;
  flowlogs)
    echo "== flow logs in $LOC"
    az network watcher flow-log list --location "$LOC" -o table
    ;;
  capture)
    ST="${STORAGE_ACCOUNT:?set STORAGE_ACCOUNT to the output storage_account}"
    echo "== start a 60 second capture on vm-server, TCP port $PORT only"
    az network watcher packet-capture create -g "$RG" -n cap-lab --vm vm-server --storage-account "$ST" \
      --time-limit 60 --filters "[{\"protocol\":\"TCP\",\"localPort\":\"$PORT\"}]" -o table
    echo "Run './scripts/netwatch-check.sh app' now, then wait 60 seconds and download the .cap blob from the storage account."
    ;;
  query)
    WS="${WORKSPACE_ID:?set WORKSPACE_ID to the output workspace_id}"
    echo "== recent flow records between the client and the server (Traffic Analytics table)"
    az monitor log-analytics query -w "$WS" --analytics-query \
      "NTANetAnalytics | where TimeGenerated > ago(1h) | where SrcIp == '$CLIENT_IP' and DestIp == '$SERVER_IP' | project TimeGenerated, FlowType, FlowStatus, DestPort, L4Protocol | take 20" -o table
    ;;
  app)
    echo "== vm-client calls vm-server on port $PORT (000 means no connection)"
    run_on vm-client "curl -s -m 5 -o /dev/null -w '%{http_code}' http://$SERVER_IP:$PORT || true"
    echo "== vm-client pings vm-server"
    run_on vm-client "ping -c 3 -W 2 $SERVER_IP | tail -2 || true"
    ;;
  *)
    echo "usage: $0 topology | routes | rules | nexthop | ipflow | connect | flowlogs | capture | query | app" >&2
    exit 2
    ;;
esac
