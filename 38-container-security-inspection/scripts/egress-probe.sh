#!/usr/bin/env bash
# Designed, not tested. Calls URLs from inside a pod, so the call takes the pod -> node -> route table -> firewall path.
# Usage: ./scripts/egress-probe.sh <namespace> <pod> <url> [url...]
set -u
ns=$1
pod=$2
shift 2
for url in "$@"; do
  code=$(kubectl exec -n "$ns" "$pod" -- curl -s -o /dev/null -m 5 -w '%{http_code}' "$url" 2>/dev/null)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    echo "OK      $code  $url"
  else
    echo "BLOCKED       $url"
  fi
done
kubectl get pod -n "$ns" "$pod" -o wide
