#!/usr/bin/env bash
# usage: register-pod-tags.sh <kube-context> <namespace> [fw-host]
# Registers each pod's IP with tags built from its namespace and labels, through the PAN-OS XML API.
# Designed, not tested. Check the current PAN-OS XML API documentation for the message format and the tag timeout.
set -u
ctx=$1; ns=$2; fw=${3:-fw1}
: "${PAN_KEY:?set PAN_KEY from a secret store}"
kubectl --context "$ctx" -n "$ns" get pods -o json |
 jq -r '.items[] | select(.status.podIP != null) |
   [.status.podIP, (["k8s-ns-"+.metadata.namespace] + [(.metadata.labels // {}) | to_entries[] | "k8s-"+.key+"-"+.value]) | join(",")] | @tsv' |
while IFS=$'\t' read -r ip tags; do
  members=$(echo "$tags" | tr ',' '\n' | sed 's|.*|<member timeout="3600">&</member>|' | tr -d '\n')
  cmd="<uid-message><version>2.0</version><type>update</type><payload><register><entry ip=\"$ip\"><tag>$members</tag></entry></register></payload></uid-message>"
  curl -sk --max-time 10 "https://${fw}/api/" --data-urlencode "type=user-id" --data-urlencode "key=$PAN_KEY" --data-urlencode "cmd=$cmd" > /dev/null && echo "registered $ip $tags"
done
