#!/usr/bin/env bash
# Designed, not tested. Pure arithmetic helper: no Azure or Kubernetes calls.
# Usage:
#   ./scripts/ipbudget.sh overlap
#   ./scripts/ipbudget.sh <overlay|node_subnet|dynamic|kubenet> <max_nodes> <surge> <max_pods> <node_subnet_prefix>
set -euo pipefail

ip2int() { local a b c d; IFS=. read -r a b c d <<<"$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }

overlaps() { # cidr1 cidr2
  local n1=${1%/*} p1=${1#*/} n2=${2%/*} p2=${2#*/}
  local s1 s2 e1 e2
  s1=$(ip2int "$n1"); s2=$(ip2int "$n2")
  e1=$(( s1 + (1 << (32 - p1)) - 1 )); e2=$(( s2 + (1 << (32 - p2)) - 1 ))
  [ "$s1" -le "$e2" ] && [ "$s2" -le "$e1" ]
}

case "${1:-}" in
  overlap)
    names=("aks-vnet" "onprem-vnet" "pod-cidr" "service-cidr")
    cidrs=("10.40.0.0/16" "10.50.0.0/16" "${POD_CIDR:-10.244.0.0/16}" "${SERVICE_CIDR:-172.20.0.0/16}")
    dns="${DNS_IP:-172.20.0.10}"
    for i in "${!cidrs[@]}"; do echo "${names[$i]} ${cidrs[$i]}"; done
    echo "dns-service-ip $dns"
    bad=0
    for i in "${!cidrs[@]}"; do
      for j in "${!cidrs[@]}"; do
        if [ "$i" -lt "$j" ] && overlaps "${cidrs[$i]}" "${cidrs[$j]}"; then
          echo "OVERLAP: ${names[$i]} ${cidrs[$i]} and ${names[$j]} ${cidrs[$j]}"; bad=1
        fi
      done
    done
    [ "$bad" -eq 0 ] && echo "no overlaps found"
    ;;
  overlay|node_subnet|dynamic|kubenet)
    model=$1; nodes=${2:?max_nodes}; surge=${3:?surge}; pods=${4:?max_pods}; prefix=${5:?prefix}
    total=$(( nodes + surge ))
    if [ "$model" = "node_subnet" ]; then need=$(( total * (1 + pods) + 5 )); else need=$(( total + 5 )); fi
    usable=$(( (1 << (32 - prefix)) - 5 ))
    echo "model=$model nodes+surge=$total need=$need usable_in_/$prefix=$usable"
    if [ "$need" -le "$usable" ]; then echo "fits"; else echo "does NOT fit"; fi
    if [ "$model" = "dynamic" ]; then echo "pod subnet needs about $(( total * pods )) addresses plus batch slack"; fi
    ;;
  *)
    echo "usage: $0 overlap | <model> <max_nodes> <surge> <max_pods> <prefix>" >&2; exit 1 ;;
esac
